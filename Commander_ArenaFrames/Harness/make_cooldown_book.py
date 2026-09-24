#!/usr/bin/env python3
"""Generate the enemy-cooldown book half of CommanderArenaFramesData.lua.

What is curated here is WHICH abilities an arena player needs to see on an
enemy -- that is a judgement call and belongs in a list a person maintains.
What is NOT curated is any NUMBER: the spell ids, the cooldown, the duration
and the rank ladder all come out of the client's own DB2 tables for this
build, because a hand-typed cooldown is wrong roughly as often as the patch
notes are subtle, and a board that says "Ice Block, 5:00" when the client
says 4:00 is worse than a board with no timer at all.

Usage (from the AddOns directory):
    python3 Commander_ArenaFrames/Harness/make_cooldown_book.py --csv <dir> \
        --out <fragment.lua>
"""

import argparse
import csv
import os
import sys
from collections import defaultdict

# Class skill lines, by SkillLine.ID. Keyed by id and not by name on purpose:
# THREE of the display names are shared by two classes each -- "Protection" is
# both the warrior tree (257) and the paladin one (267), "Holy" is paladin
# (594) and priest (56), "Restoration" is shaman (374) and druid (573). Keying
# on the name silently hands one class the other's spellbook, and the symptom
# is a paladin whose Divine Shield the board has never heard of.
CLASS_OF_SKILL = {
    26: "WARRIOR", 256: "WARRIOR", 257: "WARRIOR",
    594: "PALADIN", 267: "PALADIN", 184: "PALADIN",
    50: "HUNTER", 163: "HUNTER", 51: "HUNTER", 261: "HUNTER",
    253: "ROGUE", 38: "ROGUE", 39: "ROGUE", 40: "ROGUE",
    613: "PRIEST", 56: "PRIEST", 78: "PRIEST",
    375: "SHAMAN", 373: "SHAMAN", 374: "SHAMAN",
    237: "MAGE", 8: "MAGE", 6: "MAGE",
    355: "WARLOCK", 354: "WARLOCK", 593: "WARLOCK",
    # The warlock's control is half his demon's: Seduction, Spell Lock,
    # Devour Magic and Sacrifice are pet lines, and an arena player counts
    # every one of them as the warlock's cooldown.
    188: "WARLOCK", 189: "WARLOCK", 204: "WARLOCK", 205: "WARLOCK", 761: "WARLOCK",
    574: "DRUID", 134: "DRUID", 573: "DRUID",
}

# Racial skill lines, by SkillLine.ID -- their display names are not uniform
# ("Dwarven Racial", "Racial - Human", "Blood Elf Racial"), so a prefix test
# picks up some races and drops others.
RACE_OF_SKILL = {
    754: "Human", 101: "Dwarf", 753: "Gnome", 126: "NightElf", 760: "Draenei",
    125: "Orc", 733: "Troll", 124: "Tauren", 220: "Scourge", 756: "BloodElf",
}

# The book. One entry per ability an arena player actually reacts to, grouped
# the way a board should read it:
# A fourth field, `off`, marks an ability that belongs in the book but NOT on
# the strip by default. These are ROTATIONAL -- Mortal Strike, Mind Blast,
# Conflagrate, Tiger's Fury. Their cooldowns are six to fifteen seconds, so on
# a strip they are a light that blinks constantly and never once tells you
# anything you would act on, while eating a slot the enemy's real cooldowns
# need. They stay in the book, off by default, one click away in the per-ability
# grid -- deleting them would take the choice away, and a Blood Fury player may
# well want Mortal Strike visible.
#
# Interrupts are deliberately NOT in this category however short they are: a
# kick on cooldown is a free cast, and that is the single most valuable thing
# on the strip for any caster.
#
#   role  "DEF"  they survive with it -- stop casting, or save the burst
#         "OFF"  they kill with it -- peel, or press your own defensive
#         "CC"   the control they can land on you next
#         "KICK" an interrupt: knowing it is down is a free cast
#         "UTIL" mobility, dispels, mana
# `talent` names the talent that shortens it, when one does -- the board shows
# the client's own base number and says on the tooltip that a talent can cut it.
BOOK = {
    "WARRIOR": [
        ("Shield Wall",         "DEF",  None),
        ("Last Stand",          "DEF",  None),
        ("Spell Reflection",    "DEF",  None),
        ("Recklessness",        "OFF",  None),
        ("Death Wish",          "OFF",  None),
        ("Retaliation",         "OFF",  None),
        ("Sweeping Strikes",    "OFF",  None),
        ("Mortal Strike",       "OFF",  None, True),
        ("Intimidating Shout",  "CC",   None),
        ("Concussion Blow",     "CC",   None),
        ("Intercept",           "CC",   None),
        ("Charge",              "CC",   None),
        ("Pummel",              "KICK", None),
        ("Shield Bash",         "KICK", None),
        ("Berserker Rage",      "UTIL", None),
        ("Bloodrage",           "UTIL", None),
        ("Piercing Howl",       "UTIL", None),
    ],
    "PALADIN": [
        ("Divine Shield",           "DEF",  None),
        ("Divine Protection",       "DEF",  None),
        ("Blessing of Protection",  "DEF",  None),
        ("Lay on Hands",            "DEF",  None),
        ("Blessing of Sacrifice",   "DEF",  None),
        ("Avenging Wrath",          "OFF",  None),
        ("Divine Favor",            "OFF",  None),
        ("Hammer of Justice",       "CC",   "Improved Hammer of Justice"),
        ("Repentance",              "CC",   None),
        ("Blessing of Freedom",     "UTIL", None),
        ("Cleanse",                 "UTIL", None),
        ("Holy Shock",              "OFF",  None, True),
        ("Hammer of Wrath",         "OFF",  None, True),
    ],
    "HUNTER": [
        ("Deterrence",       "DEF",  None),
        ("Feign Death",      "DEF",  None),
        ("Readiness",        "DEF",  None),
        ("Bestial Wrath",    "OFF",  None),
        ("Rapid Fire",       "OFF",  None),
        ("Intimidation",     "CC",   None),
        ("Scatter Shot",     "CC",   None),
        ("Wyvern Sting",     "CC",   None),
        ("Freezing Trap",    "CC",   None),
        ("Scare Beast",      "CC",   None),
        ("Silencing Shot",   "KICK", None),
        ("Disengage",        "UTIL", None),
        ("Misdirection",     "UTIL", None),
    ],
    "ROGUE": [
        ("Cloak of Shadows", "DEF",  None),
        ("Evasion",          "DEF",  "Imp. Evasion"),
        ("Vanish",           "DEF",  "Elusiveness"),
        ("Preparation",      "DEF",  None),
        ("Adrenaline Rush",  "OFF",  None),
        ("Blade Flurry",     "OFF",  None),
        ("Cold Blood",       "OFF",  None),
        ("Premeditation",    "OFF",  None, True),
        ("Ghostly Strike",   "OFF",  None, True),
        ("Blind",            "CC",   "Elusiveness"),
        ("Kidney Shot",      "CC",   None),
        ("Gouge",            "CC",   None),
        ("Kick",             "KICK", None),
        ("Sprint",           "UTIL", "Imp. Sprint"),
        ("Shadowstep",       "UTIL", None),
    ],
    "PRIEST": [
        ("Pain Suppression",  "DEF",  None),
        ("Desperate Prayer",  "DEF",  None),
        ("Fear Ward",         "DEF",  None),
        ("Power Infusion",    "OFF",  None),
        ("Inner Focus",       "OFF",  None),
        ("Shadow Word: Death","OFF",  None, True),
        ("Mind Blast",        "OFF",  None, True),
        ("Psychic Scream",    "CC",   "Imp. Psychic Scream"),
        ("Silence",           "KICK", None),
        ("Mana Burn",         "UTIL", None),
        ("Dispel Magic",      "UTIL", None),
        ("Mass Dispel",       "UTIL", None),
    ],
    "SHAMAN": [
        ("Grounding Totem",     "DEF",  None),
        ("Shamanistic Rage",    "DEF",  None),
        ("Reincarnation",       "DEF",  None),
        ("Elemental Mastery",   "OFF",  None),
        ("Bloodlust",           "OFF",  None),
        ("Heroism",             "OFF",  None),
        ("Nature's Swiftness",  "OFF",  None),
        ("Earth Shock",         "KICK", None),
        ("Tremor Totem",        "UTIL", None),
        ("Earthbind Totem",     "UTIL", None),
        ("Mana Tide Totem",     "UTIL", None),
        ("Purge",               "UTIL", None),
        ("Stoneclaw Totem",     "UTIL", None),
    ],
    "MAGE": [
        ("Ice Block",         "DEF",  None),
        ("Ice Barrier",       "DEF",  None),
        ("Invisibility",      "DEF",  None),
        ("Cold Snap",         "DEF",  None),
        ("Evocation",         "DEF",  None),
        ("Icy Veins",         "OFF",  None),
        ("Arcane Power",      "OFF",  None),
        ("Presence of Mind",  "OFF",  None),
        ("Polymorph",         "CC",   None),
        ("Frost Nova",        "CC",   "Imp. Frost Nova"),
        ("Dragon's Breath",   "CC",   None),
        ("Blast Wave",        "CC",   None),
        ("Counterspell",      "KICK", None),
        ("Blink",             "UTIL", None),
        ("Spellsteal",        "UTIL", None),
        ("Remove Lesser Curse", "UTIL", None),
    ],
    "WARLOCK": [
        ("Soulshatter",       "DEF",  None),
        ("Sacrifice",         "DEF",  None),
        ("Fel Domination",    "DEF",  None),
        ("Shadowburn",        "OFF",  None, True),
        ("Conflagrate",       "OFF",  None, True),
        ("Amplify Curse",     "OFF",  None),
        ("Death Coil",        "CC",   None),
        ("Howl of Terror",    "CC",   "Improved Howl of Terror"),
        ("Shadowfury",        "CC",   None),
        ("Seduction",         "CC",   None),
        ("Spell Lock",        "KICK", None),
        ("Devour Magic",      "UTIL", None),
    ],
    "DRUID": [
        ("Barkskin",           "DEF",  None),
        ("Rebirth",            "DEF",  None),
        ("Innervate",          "OFF",  None),
        ("Nature's Swiftness", "OFF",  None),
        ("Tiger's Fury",       "OFF",  None, True),
        ("Bash",               "CC",   "Brutal Impact"),
        ("Cyclone",            "CC",   None),
        ("Maim",               "CC",   None),
        ("Feral Charge",       "CC",   None),
        ("Nature's Grasp",     "CC",   None),
        ("Dash",               "UTIL", None),
        ("Travel Form",        "UTIL", None),
    ],
}

# Racials: the ones an arena opener plans around. Attributed to the RACE, not
# a class, so the board can show them on any enemy whose race it can read.
RACIALS = {
    "Human":     [("Perception", "UTIL")],
    "Dwarf":     [("Stoneform", "DEF")],
    "Gnome":     [("Escape Artist", "UTIL")],
    "NightElf":  [("Shadowmeld", "DEF")],
    "Draenei":   [("Gift of the Naaru", "DEF")],
    "Orc":       [("Blood Fury", "OFF")],
    "Troll":     [("Berserking", "OFF")],
    "Tauren":    [("War Stomp", "CC")],
    "Scourge":   [("Will of the Forsaken", "DEF"), ("Cannibalize", "UTIL")],
    "BloodElf":  [("Arcane Torrent", "KICK")],
}


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def to_int(value, default=0):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def load(csv_dir):
    names = {}
    for row in read_csv(os.path.join(csv_dir, "SpellName.csv")):
        names[to_int(row["ID"])] = row["Name_lang"]

    # RecoveryTime is the spell's own cooldown; CategoryRecoveryTime is the
    # shared-category one (traps, totems, potions). Whichever is larger is the
    # wait the enemy actually has, which is the only number the board means.
    cooldown = {}
    for row in read_csv(os.path.join(csv_dir, "SpellCooldowns.csv")):
        spell = to_int(row.get("SpellID") or row.get("ID"))
        best = max(to_int(row.get("RecoveryTime")), to_int(row.get("CategoryRecoveryTime")))
        if best:
            cooldown[spell] = max(cooldown.get(spell, 0), best)

    durations = {}
    for row in read_csv(os.path.join(csv_dir, "SpellDuration.csv")):
        durations[to_int(row["ID"])] = to_int(row["Duration"])

    duration_of = {}
    for row in read_csv(os.path.join(csv_dir, "SpellMisc.csv")):
        spell = to_int(row.get("SpellID") or row.get("ID"))
        idx = to_int(row.get("DurationIndex"))
        if idx and idx in durations:
            duration_of[spell] = durations[idx]

    skill_names = {}
    for row in read_csv(os.path.join(csv_dir, "SkillLine.csv")):
        skill_names[to_int(row["ID"])] = row.get("DisplayName_lang", "")

    by_class = defaultdict(lambda: defaultdict(list))   # class -> name -> [ids]
    racial = defaultdict(lambda: defaultdict(list))     # race  -> name -> [ids]
    for row in read_csv(os.path.join(csv_dir, "SkillLineAbility.csv")):
        spell = to_int(row["Spell"])
        line_id = to_int(row["SkillLine"])
        name = names.get(spell)
        if not name:
            continue
        klass = CLASS_OF_SKILL.get(line_id)
        if klass:
            by_class[klass][name].append(spell)
        race = RACE_OF_SKILL.get(line_id)
        if race:
            racial[race][name].append(spell)

    return names, cooldown, duration_of, by_class, racial


def pick(ids, cooldown):
    """The rank a level-70 enemy is casting: the highest id that HAS the
    cooldown we mean. Highest id is the right tiebreak in TBC -- ranks are
    added in ascending id order within an expansion."""
    ids = sorted(ids)
    with_cd = [i for i in ids if cooldown.get(i)]
    return (with_cd or ids)[-1] if ids else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--build", default="2.5.6.69546")
    args = ap.parse_args()

    names, cooldown, duration_of, by_class, racial_lines = load(args.csv)

    lines = ["-- GENERATED by Harness/make_cooldown_book.py -- do not hand-edit.",
             "-- Client build %s. Which abilities are listed is curated; every" % args.build,
             "-- number below is the client's own (SpellCooldowns / SpellDuration).",
             "",
             "DATA.ENEMY_BOOK = {"]
    missing, nocd, kept = [], [], 0
    for klass in sorted(BOOK):
        lines.append('    %s = {' % klass)
        for entry_spec in BOOK[klass]:
            name, role, talent = entry_spec[0], entry_spec[1], entry_spec[2]
            default_off = len(entry_spec) > 3 and entry_spec[3]
            ids = by_class[klass].get(name)
            if not ids:
                missing.append("%s/%s" % (klass, name))
                continue
            spell = pick(ids, cooldown)
            cd = cooldown.get(spell, 0) / 1000.0
            dur = duration_of.get(spell, 0) / 1000.0
            # An ability with no cooldown has nothing for a cooldown strip to
            # count down, and putting one there is a slot that never changes.
            # Reported rather than silently dropped, so the curated list above
            # stays honest about what it asked for.
            if cd <= 0:
                nocd.append("%s/%s" % (klass, name))
                continue
            kept += 1
            parts = ['id = %d' % spell, 'name = "%s"' % name.replace('"', '\\"'),
                     'role = "%s"' % role, 'cd = %s' % ("%g" % cd)]
            if dur > 0:
                parts.append('dur = %g' % dur)
            if talent:
                parts.append('talent = "%s"' % talent)
            if default_off:
                parts.append("off = true")
            lines.append("        { %s }," % ", ".join(parts))
        lines.append("    },")
    lines.append("}")
    lines.append("")

    lines.append("DATA.RACIAL_BOOK = {")
    for race in sorted(RACIALS):
        entries = []
        for name, role in RACIALS[race]:
            ids = racial_lines.get(race, {}).get(name)
            if not ids:
                missing.append("%s/%s" % (race, name))
                continue
            spell = pick(ids, cooldown)
            cd = cooldown.get(spell, 0) / 1000.0
            dur = duration_of.get(spell, 0) / 1000.0
            parts = ['id = %d' % spell, 'name = "%s"' % name,
                     'role = "%s"' % role, 'cd = %g' % cd]
            if dur > 0:
                parts.append('dur = %g' % dur)
            entries.append("        { %s }," % ", ".join(parts))
            kept += 1
        if entries:
            lines.append('    %s = {' % race)
            lines.extend(entries)
            lines.append("    },")
    lines.append("}")
    lines.append("")

    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    print("kept %d entries -> %s" % (kept, args.out))
    if missing:
        print("NOT FOUND in the client's tables (%d):" % len(missing))
        for entry in missing:
            print("   ", entry)
    if nocd:
        print("dropped, no cooldown in the client's tables (%d): %s"
              % (len(nocd), ", ".join(nocd)))


if __name__ == "__main__":
    main()
