#!/usr/bin/env python3
"""Generate CommanderQuestLogAttuneData.lua: the attunement guides the
Attunements tab lists and the engine (CommanderQuestLogAttune.lua) ticks off.

Why a generator. The guides were researched as seven JSON bundles
(Harness/attune_research/research-0..6.json), each a {topic, data, verify}
record whose verify.corrections rows are the auditor's fixes to the
researcher's data. Nothing in the client answers "what does Karazhan need":
every quest id, item id, faction id, NPC and coordinate below is research,
and the only honest way to ship research is to apply every correction row
mechanically and refuse to emit when a row cannot be applied. The tab's
words (Done, To do, Locked...) and its "How the tab knows" sentences are the
engine's; this file carries no prose about detection (detectedBy is dropped).

What it does, in order (DESIGN.md section 3.8):
  1. load the seven bundles; PHASES becomes D.PHASES[n].notes
  2. apply EVERY verify.corrections row through a handler keyed on
     (guideKey, stepKey, field); a prose row whose `from` is found verbatim
     is a text replacement, every other row has a hand-written handler, and
     an unhandled row is a hard error
  3. map every research field to the Lua record (section 3.8.3), dropping
     only what the table says to drop
  4. look zones up in MAPS (parentheticals stripped) or INSTANCE_NAMES
  5. merge BADGES_PHASE_1..5 and BADGE_VENDORS into one recurring BADGES
     guide, and FLYING_BASIC and FLYING_EPIC into FLYING
  6. stamp the hand tables (names, windows, alternatives, unlock proofs,
     implication, consumption, levels, mounts, prerequisites...)
  7. emit the Lua: header, top tables, one do-block per guide
  8. --check: regenerate in memory, compare byte for byte, run the invariants

Run:
    python3 Commander_QuestLog/Harness/make_attunements.py                # write the data file
    python3 Commander_QuestLog/Harness/make_attunements.py --check        # exit 1 if stale or an invariant fails
    python3 Commander_QuestLog/Harness/make_attunements.py --research DIR # bundles elsewhere
    python3 Commander_QuestLog/Harness/make_attunements.py --verify-ids   # also ask Wowhead's Anniversary tooltip
                                                                          # endpoint about the three mount ids (A80)

The report on stdout lists guides, steps per kind, every correction row and
how it was applied, what was dropped, and the byte count. See ../DECISIONS.md
D54, D56, D57 and ../ASSUMPTIONS.md A73, A74, A80, A81.
"""
import argparse
import copy
import json
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.dirname(HERE)
ADDONS = os.path.dirname(MODULE)

BUILD = "2026-10-24"     # the research bundles' date
SOURCE = "research-0..6.json via Harness/make_attunements.py"
DEFAULT_RESEARCH = os.path.join(HERE, "attune_research")
DEFAULT_OUT = os.path.join(MODULE, "CommanderQuestLogAttuneData.lua")
WARN_BYTES = 400 * 1024
WOWHEAD = "https://nether.wowhead.com/tooltip/item/%d?dataEnv=5&locale=0"

# ===========================================================================
# Hand tables (section 3.8.6 and the phase and rule rows of 3.2 and 3.3)
# ===========================================================================

CATEGORIES = [
    ("RAID", "Raid attunements"), ("HEROIC", "Heroic keys"), ("DUNGEON", "Dungeon keys"),
    ("UNLOCK", "Reputation hubs"), ("FLYING", "Flying"), ("BADGES", "Badges of Justice"),
]

# Five epoch starts (research-6 section 7, recomputed by its verifier): seconds since the
# epoch, compared against GetServerTime(); False = unannounced.
PHASES = [
    dict(n=1, short="Phase 1", name="The Burning Crusade", blizzard="Phase 1", since=1770332400, raidsOpen=1771542000),
    dict(n=2, short="Phase 2", name="Overlords of Outland", blizzard="Phase 2", since=1778796000),
    dict(n=3, short="Phase 3", name="The Black Temple", blizzard="Phase 3", since=1787868000),
    dict(n=4, short="Phase 4", name="The Gods of Zul'Aman", blizzard="Phase 3.5", since=1792706400),
    dict(n=5, short="Phase 5", name="Fury of the Sunwell", blizzard="Phase 4", since=False),
]

# The research PHASES details are 2,000-character paragraphs full of item and quest ids.
# This table carries, per phase, the notes the phase button's tooltip and the overview's
# THIS PHASE block show (three or four sentences written from the corrected research
# detail) and the THIS PHASE rule sentences of RULES[n].sentences. Plain English, British
# spelling, no symbols.
PHASE_SENTENCES = {
    1: dict(
        notes=("The Burning Crusade launched on 5 February 2026 at 3 pm Pacific; Karazhan, Gruul's Lair and "
               "Magtheridon's Lair opened two weeks later on 19 February. Every heroic key costs Revered, Karazhan "
               "needs The Master's Key from its attunement chain, and a raid attunement done once unlocks that raid "
               "for the whole account. Badges of Justice drop only from heroic dungeon bosses and Wind Trader "
               "Zhareem's heroic daily, and G'eras in Shattrath is the only badge vendor. Flying is available at "
               "level 70 from launch."),
        sentences=[
            "Heroic dungeon keys are sold at Revered.",
            "Karazhan needs The Master's Key in the raid; Serpentshrine Cavern, Tempest Keep, Mount Hyjal and the Black Temple are not open yet.",
            "Badges of Justice drop only from heroic dungeon bosses and Wind Trader Zhareem's heroic daily.",
            "Karazhan, Gruul's Lair and Magtheridon's Lair are open.",
            "Next: Phase 2, Overlords of Outland, from 14 May 2026.",
        ]),
    2: dict(
        notes=("Overlords of Outland went live on 14 May 2026 and opened Serpentshrine Cavern and Tempest Keep in "
               "their reduced state, the Ogri'la and Sha'tari Skyguard daily hubs, the druid Swift Flight Form chain "
               "and new recipes. Both raids need their attunement for the whole phase: the Cudgel of Kar'desh for "
               "Serpentshrine Cavern and the Tempest Key for Tempest Keep. A character at Revered can buy a Communal "
               "pouch whose heroic key an alt uses at Friendly. Heroic keys still cost Revered, badges still come "
               "only from heroics, and Mount Hyjal and the Black Temple are closed."),
        sentences=[
            "Heroic dungeon keys are sold at Revered; a character at Revered can buy a Communal pouch for the account's alts.",
            "Karazhan needs The Master's Key in the raid; Serpentshrine Cavern needs The Cudgel of Kar'desh and Tempest Keep needs The Tempest Key.",
            "Badges of Justice still drop only from heroic dungeon bosses and the heroic daily.",
            "Serpentshrine Cavern, Tempest Keep, Ogri'la and the Sha'tari Skyguard are open; druids can learn Swift Flight Form.",
            "Next: Phase 3, The Black Temple, from 27 August 2026.",
        ]),
    3: dict(
        notes=("The Black Temple phase went live on 27 August 2026 and opened the Battle for Mount Hyjal, which needs "
               "The Vials of Eternity, and the Black Temple, which needs the Medallion of Karabor from the Ashtongue "
               "chain. The Serpentshrine Cavern and Tempest Keep attunements were removed the same day and the skips "
               "to Lady Vashj and Kael'thas were enabled; Karazhan still needs The Master's Key. The Netherwing daily "
               "hub opened in Shadowmoon Valley with epic drakes at Exalted. Heroic keys still cost Revered, no raid "
               "boss drops badges, and Zul'Aman and the Isle of Quel'Danas are closed."),
        sentences=[
            "Heroic dungeon keys are sold at Revered.",
            "Karazhan still needs The Master's Key in the raid; Serpentshrine Cavern and Tempest Keep need no attunement any more; Mount Hyjal needs The Vials of Eternity and the Black Temple needs the Medallion of Karabor.",
            "Badges of Justice still drop only from heroic dungeon bosses and the heroic daily.",
            "Mount Hyjal, the Black Temple and the Netherwing dailies are open.",
            "Next: Phase 4, The Gods of Zul'Aman, from 22 October 2026.",
        ]),
    4: dict(
        notes=("The Gods of Zul'Aman, which Blizzard calls Phase 3.5, went live on 22 October 2026 and opened "
               "Zul'Aman, a ten player raid with six bosses, no attunement and a three day lockout. Mount Hyjal and "
               "the Black Temple no longer need an attunement, heroic dungeon keys are sold at Honored, and every "
               "heroic dungeon is at its final reduced difficulty. Badges of Justice now drop from Doom Lord Kazzak, "
               "Doomwalker and every boss in Karazhan, Gruul's Lair, Magtheridon's Lair, Serpentshrine Cavern, "
               "Tempest Keep and Zul'Aman, but not from Mount Hyjal or the Black Temple. G'eras sells stronger wares "
               "and the Nether Vortex, and Primal Nethers and Nether Vortexes are no longer soulbound."),
        sentences=[
            "Heroic dungeon keys are sold at Honored.",
            "Karazhan still needs The Master's Key in the raid; Mount Hyjal and the Black Temple need no attunement any more.",
            "Badges of Justice drop from every boss in Karazhan, Zul'Aman, Gruul's Lair, Magtheridon's Lair, Serpentshrine Cavern and Tempest Keep, and from Doom Lord Kazzak and Doomwalker.",
            "Zul'Aman is open with a three day lockout.",
            "Next: Phase 5, Fury of the Sunwell, has no announced date.",
        ]),
    5: dict(
        notes=("Fury of the Sunwell, which Blizzard calls Phase 4, has no announced date; Blizzard's roadmap lists it "
               "for later in 2026. It brings the Isle of Quel'Danas with the Shattered Sun Offensive and its realm "
               "wide progression, Magisters' Terrace in normal and heroic, Sunwell Plateau with no attunement, and "
               "Arena Season 4. New vendors unlock on the Isle as the staging area is reinforced: Smith Hauthaa sells "
               "badge gear once the Anvil and Forge are rebuilt and Shaani sells uncut epic gems. Mount Hyjal and "
               "Black Temple bosses are expected to drop badges as they did in the original patch, but that is not "
               "confirmed."),
        sentences=[
            "Heroic dungeon keys are sold at Honored.",
            "Karazhan still needs The Master's Key in the raid; no other raid needs an attunement; heroic Magisters' Terrace opens with Hard to Kill.",
            "Badges of Justice drop from every raid boss, from Magisters' Terrace and the world bosses, and a Shattered Sun Supplies bag can hold one.",
            "The Isle of Quel'Danas, Magisters' Terrace and Sunwell Plateau are open; the Isle's vendors unlock as the realm's Shattered Sun Offensive advances.",
            "Phase 5 is the last phase of The Burning Crusade.",
        ]),
}

GATE_KEYS = ["KARAZHAN", "SSC", "TK", "HYJAL", "BT"]
BADGE_KEYS = ["HEROIC", "DAILY_HEROIC", "KARAZHAN", "GRUUL_MAG", "SSC_TK", "ZA", "ZA_QUESTS", "WORLD_BOSS",
              "HYJAL_BT", "SUNWELL", "MGT", "ISLE"]
LIVE_KEYS = ["OGRILA", "SKYGUARD", "NETHERWING", "ZA", "SUNWELL", "MGT", "ISLE"]

# One FULL row per phase (section 3.3); nothing inherited.
RULE_ROWS = {
    1: dict(heroicKeyStanding=7, communalPouches=False, heroicTuning="launch", vendorStock="launch",
            required=["KARAZHAN", "SSC", "TK", "HYJAL", "BT"], raidsOpen=[532, 565, 544],
            badges=["HEROIC", "DAILY_HEROIC"], live=[], assumed=[]),
    2: dict(heroicKeyStanding=7, communalPouches=True, heroicTuning="launch", vendorStock="launch",
            required=["KARAZHAN", "SSC", "TK", "HYJAL", "BT"], raidsOpen=[532, 565, 544, 548, 550],
            badges=["HEROIC", "DAILY_HEROIC"], live=["OGRILA", "SKYGUARD"], assumed=[]),
    3: dict(heroicKeyStanding=7, communalPouches=True, heroicTuning="launch", vendorStock="launch",
            required=["KARAZHAN", "HYJAL", "BT"], raidsOpen=[532, 565, 544, 548, 550, 534, 564],
            badges=["HEROIC", "DAILY_HEROIC"], live=["OGRILA", "SKYGUARD", "NETHERWING"], assumed=[]),
    4: dict(heroicKeyStanding=6, communalPouches=True, heroicTuning="final", vendorStock="expanded",
            required=["KARAZHAN"], raidsOpen=[532, 565, 544, 548, 550, 534, 564, 568],
            badges=["HEROIC", "DAILY_HEROIC", "KARAZHAN", "GRUUL_MAG", "SSC_TK", "ZA", "ZA_QUESTS", "WORLD_BOSS"],
            live=["OGRILA", "SKYGUARD", "NETHERWING", "ZA"], assumed=[]),
    5: dict(heroicKeyStanding=6, communalPouches=True, heroicTuning="final", vendorStock="isle",
            required=["KARAZHAN"], raidsOpen=[532, 565, 544, 548, 550, 534, 564, 568, 580],
            badges=BADGE_KEYS, live=LIVE_KEYS, assumed=["heroicKeyStanding", "badgeSources.HYJAL_BT"]),
}

EVIDENCE = dict(
    lockouts={568: 4, 580: 5, 585: 5},
    quests={11130: 4, 11132: 4, 11166: 4, 11171: 4, 11163: 4, 11178: 4, 11481: 5, 11482: 5, 11488: 5},
)

# Navigator names, 24 characters or fewer.
NAMES = {
    "KARAZHAN_ATTUNEMENT": "Karazhan", "NIGHTBANE_SUMMON": "Nightbane", "GRUUL_MAGTHERIDON": "Gruul and Magtheridon",
    "SSC_ATTUNEMENT": "Serpentshrine Cavern", "TK_ATTUNEMENT": "Tempest Keep", "HYJAL_ATTUNEMENT": "Mount Hyjal",
    "BLACK_TEMPLE_ATTUNEMENT": "Black Temple", "ZUL_AMAN": "Zul'Aman", "SUNWELL_PLATEAU": "Sunwell Plateau",
    "HEROIC_HELLFIRE": "Heroic Hellfire", "HEROIC_COILFANG": "Heroic Coilfang", "HEROIC_AUCHINDOUN": "Heroic Auchindoun",
    "HEROIC_TEMPEST_KEEP": "Heroic Tempest Keep", "HEROIC_CAVERNS_OF_TIME": "Heroic Caverns of Time",
    "HEROIC_MAGISTERS_TERRACE": "Magisters' Terrace",
    "CAVERNS_OF_TIME_ACCESS": "Caverns of Time", "SHADOW_LABYRINTH_KEY": "Shadow Labyrinth Key",
    "SHATTERED_HALLS_KEY": "Shattered Halls Key", "ARCATRAZ_KEY": "Arcatraz Key",
    "ALDOR_SCRYER_CHOICE": "Aldor or Scryers", "OGRILA_UNLOCK": "Ogri'la", "SKYGUARD_SKETTIS": "Sha'tari Skyguard",
    "NETHERWING_DAILIES": "Netherwing", "SHATTERED_SUN_OFFENSIVE": "Shattered Sun Offensive",
    "FLYING": "Flying", "BADGES": "Badges of Justice",
}

MERGED = {"FLYING_BASIC": "FLYING", "FLYING_EPIC": "FLYING", "BADGE_VENDORS": "BADGES",
          "BADGES_PHASE_1": "BADGES", "BADGES_PHASE_2": "BADGES", "BADGES_PHASE_3": "BADGES",
          "BADGES_PHASE_4": "BADGES", "BADGES_PHASE_5": "BADGES"}
DROPPED_GUIDES = {"PHASES"}       # its five texts feed D.PHASES[n].notes, it is not a guide

# Prerequisite rows that are recommendations (research-3 corrections on Hyjal and the Black Temple).
SOFT = {"HYJAL_ATTUNEMENT": {"SSC_ATTUNEMENT", "TK_ATTUNEMENT"},
        "BLACK_TEMPLE_ATTUNEMENT": {"HYJAL_ATTUNEMENT", "SSC_ATTUNEMENT", "TK_ATTUNEMENT"}}

# Prerequisite rows the research arrays leave out, appended after them (3.8.6, lead decision on the
# data fixer's round 1). research-3 #10 softens the Black Temple's three raid rows and names its hard
# requirements as "level 70 plus an Aldor or Scryer pledge": level 70 is MIN_LEVEL, and the pledge is
# this row. QuestieDB gates the chain's first quest on it: Tablets of Baa'ri 10568 (Aldor) needs
# requiredMinRep {932, 3000} and its Scryer twin 10683 needs preQuestSingle {10552} plus
# requiredMinRep {934, 3000}, so without a pledge neither version can be taken. Hyjal gets no row
# (research-3 #9: level 70 and the two boss kills are its only hard requirements).
PREREQS = {"BLACK_TEMPLE_ATTUNEMENT": [{"guide": "ALDOR_SCRYER_CHOICE", "hard": True}]}

# Steps forced optional beyond the research's own flag.
OPTIONAL = {"KARAZHAN_ATTUNEMENT": {"shadow_lab_key_access", "arcatraz_key_access"},
            "HEROIC_HELLFIRE": {"communal_key"}, "HEROIC_COILFANG": {"communal_key"},
            "HEROIC_AUCHINDOUN": {"communal_key"}, "HEROIC_TEMPEST_KEEP": {"communal_key"},
            "HEROIC_CAVERNS_OF_TIME": {"communal_key"}, "HEROIC_MAGISTERS_TERRACE": {"sunwell_summons"}}

MIN_LEVEL = {"NIGHTBANE_SUMMON": 70, "ZUL_AMAN": 70, "SUNWELL_PLATEAU": 70, "SSC_ATTUNEMENT": 70, "TK_ATTUNEMENT": 70,
             "HYJAL_ATTUNEMENT": 70, "BLACK_TEMPLE_ATTUNEMENT": 70, "OGRILA_UNLOCK": 70, "SKYGUARD_SKETTIS": 70,
             "NETHERWING_DAILIES": 70, "SHATTERED_SUN_OFFENSIVE": 70, "BADGES": 70}

ACCOUNT_WIDE = ["KARAZHAN_ATTUNEMENT", "SSC_ATTUNEMENT", "TK_ATTUNEMENT", "HYJAL_ATTUNEMENT", "BLACK_TEMPLE_ATTUNEMENT"]

# Faction.db2 70006 (reader-client-api): the authored names, for a faction the character never met.
FACTIONS = {946: "Honor Hold", 947: "Thrallmar", 942: "Cenarion Expedition", 1011: "Lower City", 935: "The Sha'tar",
            989: "Keepers of Time", 933: "The Consortium", 1077: "Shattered Sun Offensive", 1015: "Netherwing",
            1038: "Ogri'la", 1031: "Sha'tari Skyguard", 967: "The Violet Eye", 1012: "Ashtongue Deathsworn",
            990: "The Scale of the Sands", 932: "The Aldor", 934: "The Scryers"}

AUTO = {"set_heroic": {"dungeonDifficulty": 2}}      # by step key, every guide
ALLOW_UNKNOWN = set()                                # "GUIDE:step" allowed to stay UNKNOWN; empty for 1.8.0

# 3.8.6 names the two BADGES pools; HEROIC_HELLFIRE's fortifications_daily is stamped too because the
# 3.9 example emits it with daily = true and the research left the flag off a quest that is a daily.
DAILY = {"BADGES": {"heroic_daily", "sso_supplies"}, "HEROIC_HELLFIRE": {"fortifications_daily"}}
ALL_OF = {"BADGES": {"za_quests"}}
FULL_CLEAR = {"BADGES": {"karazhan", "zulaman"}}
LEVEL = {"FLYING": {"artisan_riding": 70, "epic_flying_mount": 70, "swift_flight_form": 70}}

# Section 3.6: every 60 percent id and every 280 percent id, both factions (ANY).
MOUNTS = dict(
    basic=dict(A=[25470, 25471, 25472], H=[25474, 25475, 25476], ANY=[34060]),
    epic=dict(A=[25473, 25527, 25528, 25529], H=[25477, 25531, 25532, 25533],
              ANY=[32857, 32858, 32859, 32860, 32861, 32862,          # the six Netherwing drakes
                   32314, 32316, 32317, 32318, 32319,                 # the five Skyguard nether rays
                   33999, 32458, 34061]),                             # A80: Hippogryph, Ashes of Al'ar, Turbo-Charged Control
)
VERIFY_IDS = {33999: "Cenarion War Hippogryph", 32458: "Ashes of Al'ar", 34061: "Turbo-Charged Flying Machine Control"}

# Linear chains QuestieDB's preQuestSingle rows confirm; siblings never imply each other.
IMPLIED = ["KARAZHAN_ATTUNEMENT", "CAVERNS_OF_TIME_ACCESS", "NIGHTBANE_SUMMON", "SHATTERED_HALLS_KEY", "ALDOR_SCRYER_CHOICE"]
SIBLINGS = {"KARAZHAN_ATTUNEMENT": [[9824, 9825]]}

CONSUMED = {
    "KARAZHAN_ATTUNEMENT": {"second_fragment_steamvault": "the_second_and_third_fragments",
                            "third_fragment_arcatraz": "the_second_and_third_fragments"},
    "SSC_ATTUNEMENT": {"earthen_signet": "turn_in_cudgel", "blazing_signet": "turn_in_cudgel"},
    "HYJAL_ATTUNEMENT": {"vashj_remnant": "turn_in_vials", "kael_remnant": "turn_in_vials"},
    "SHATTERED_HALLS_KEY": {"primed_key_mold": "entry_into_citadel"},
}

UNLOCK = {
    "KARAZHAN_ATTUNEMENT": dict(quest=9837, items=[24490]),
    "HEROIC_HELLFIRE": dict(items=[30622, 30637, 265830, 265826]),
    "HEROIC_COILFANG": dict(items=[30623, 265843]),
    "HEROIC_AUCHINDOUN": dict(items=[30633, 265845]),
    "HEROIC_TEMPEST_KEEP": dict(items=[30634, 265847]),
    "HEROIC_CAVERNS_OF_TIME": dict(items=[30635, 265849]),
    "HEROIC_MAGISTERS_TERRACE": dict(quest=11492),
    "SHADOW_LABYRINTH_KEY": dict(items=[27991]),
    "SHATTERED_HALLS_KEY": dict(items=[28395]),      # confirmed against the research turn-in step below
    "ARCATRAZ_KEY": dict(items=[31084]),
    "CAVERNS_OF_TIME_ACCESS": dict(quest=10285),
}

ALTERNATIVES = {
    "SHADOW_LABYRINTH_KEY": {"door": dict(groups=[["kill_ikiss", "loot_key"], ["lockpick_alt"]], prefer={})},
    "ARCATRAZ_KEY": {"door": dict(groups=[
        ["crystal_collection", "heap_of_ethereals", "warp_raider_nesaad", "request_for_assistance",
         "rightful_repossession", "audience_with_prince", "triangulation_one", "triangulation_two", "full_triangle",
         "special_delivery", "kill_warp_splinter", "kill_pathaleon", "break_into_arcatraz", "arcatraz_key"],
        ["lockpick_alt"]], prefer={})},
    "FLYING": {
        "flight60": dict(groups=[["expert_riding", "flying_mount"], ["flight_form"]], prefer={"DRUID": 2}),
        "flight280": dict(groups=[["artisan_riding", "epic_flying_mount"], ["artisan_riding", "swift_flight_form"]],
                          prefer={"DRUID": 2}),
    },
}
# Steps HIDDEN for other classes (3.6).
CLASSES = {"SHADOW_LABYRINTH_KEY": {"lockpick_alt": ["ROGUE"]}, "ARCATRAZ_KEY": {"lockpick_alt": ["ROGUE"]},
           "SHATTERED_HALLS_KEY": {"lockpick_alt": ["ROGUE"]},
           "FLYING": {"flight_form": ["DRUID"], "swift_flight_form": ["DRUID"]}}

GATES = {"KARAZHAN_ATTUNEMENT": "KARAZHAN", "SSC_ATTUNEMENT": "SSC", "TK_ATTUNEMENT": "TK",
         "HYJAL_ATTUNEMENT": "HYJAL", "BLACK_TEMPLE_ATTUNEMENT": "BT"}

# The door each guide opens (guide.instance; also the auto.enteredInstance of its open_/enter_ steps).
GUIDE_INSTANCE = {"KARAZHAN_ATTUNEMENT": 532, "NIGHTBANE_SUMMON": 532, "GRUUL_MAGTHERIDON": 565, "SSC_ATTUNEMENT": 548,
                  "TK_ATTUNEMENT": 550, "HYJAL_ATTUNEMENT": 534, "BLACK_TEMPLE_ATTUNEMENT": 564, "ZUL_AMAN": 568,
                  "SUNWELL_PLATEAU": 580, "HEROIC_HELLFIRE": 540, "HEROIC_COILFANG": 545, "HEROIC_AUCHINDOUN": 555,
                  "HEROIC_TEMPEST_KEEP": 552, "HEROIC_CAVERNS_OF_TIME": 269, "HEROIC_MAGISTERS_TERRACE": 585,
                  "CAVERNS_OF_TIME_ACCESS": 269, "SHADOW_LABYRINTH_KEY": 555, "SHATTERED_HALLS_KEY": 540,
                  "ARCATRAZ_KEY": 552}

# Display names of the 25 TBC instances (plus Outland, which the world-boss KILL step names).
INSTANCES = {532: "Karazhan", 565: "Gruul's Lair", 544: "Magtheridon's Lair", 548: "Serpentshrine Cavern",
             550: "Tempest Keep: The Eye", 534: "Hyjal Summit", 564: "Black Temple", 568: "Zul'Aman",
             580: "Sunwell Plateau", 543: "Hellfire Ramparts", 542: "The Blood Furnace", 540: "The Shattered Halls",
             547: "The Slave Pens", 546: "The Underbog", 545: "The Steamvault", 557: "Mana-Tombs",
             558: "Auchenai Crypts", 556: "Sethekk Halls", 555: "Shadow Labyrinth", 554: "The Mechanar",
             553: "The Botanica", 552: "The Arcatraz", 560: "Old Hillsbrad Foothills", 269: "The Black Morass",
             585: "Magisters' Terrace", 530: "Outland"}
RAID_INSTANCES = {532, 565, 544, 548, 550, 534, 564, 568, 580}

# A zone string that names an instance (after its parenthetical is stripped) maps to the instance.
INSTANCE_NAMES = {name: mid for mid, name in INSTANCES.items() if mid != 530}
INSTANCE_NAMES.update({"Coilfang Reservoir: The Steamvault": 545, "Tempest Keep": 550, "The Battle for Mount Hyjal": 534,
                       "Magister's Terrace": 585, "Outland world bosses": 530})

# Questie area ids of the 25 instances (QuestieDB zones.lua) -> instance map id.
AREA_TO_INSTANCE = {2366: 269, 2367: 560, 3457: 532, 3562: 543, 3606: 534, 3607: 548, 3713: 542, 3714: 540,
                    3715: 545, 3716: 546, 3717: 547, 3789: 555, 3790: 558, 3791: 556, 3792: 557, 3805: 568,
                    3836: 544, 3845: 550, 3847: 553, 3848: 552, 3849: 554, 3923: 565, 3959: 564, 4075: 580, 4131: 585}

# Zone -> uiMapId (A74).
MAPS = {"Hellfire Peninsula": 1944, "Zangarmarsh": 1946, "Terokkar Forest": 1952, "Nagrand": 1951,
        "Blade's Edge Mountains": 1949, "Netherstorm": 1953, "Shadowmoon Valley": 1948, "Shattrath City": 1955,
        "Deadwind Pass": 1430, "Tanaris": 1446, "Ghostlands": 1942, "Isle of Quel'Danas": 1957, "Alterac Mountains": 1416}

# DungeonEncounter.db2 70006 (reader-client-api), by instance then English boss name.
ENCOUNTERS = {
    532: {"Attumen the Huntsman": 652, "Moroes": 653, "Maiden of Virtue": 654, "Opera Hall": 655, "The Curator": 656,
          "Terestian Illhoof": 657, "Shade of Aran": 658, "Netherspite": 659, "Chess Event": 660,
          "Prince Malchezaar": 661, "Nightbane": 662},
    565: {"High King Maulgar": 649, "Gruul the Dragonkiller": 650},
    544: {"Magtheridon": 651},
    548: {"Hydross the Unstable": 623, "The Lurker Below": 624, "Leotheras the Blind": 625,
          "Fathom-Lord Karathress": 626, "Morogrim Tidewalker": 627, "Lady Vashj": 628},
    550: {"Al'ar": 730, "Void Reaver": 731, "High Astromancer Solarian": 732, "Kael'thas Sunstrider": 733},
    534: {"Rage Winterchill": 618, "Anetheron": 619, "Kaz'rogal": 620, "Azgalor": 621, "Archimonde": 622},
    564: {"High Warlord Naj'entus": 601, "Supremus": 602, "Shade of Akama": 603, "Teron Gorefiend": 604,
          "Gurtogg Bloodboil": 605, "Reliquary of Souls": 606, "Mother Shahraz": 607, "The Illidari Council": 608,
          "Illidan Stormrage": 609},
    568: {"Akil'zon": 1189, "Nalorakk": 1190, "Jan'alai": 1191, "Halazzi": 1192, "Hex Lord Malacrass": 1193, "Zul'jin": 1194},
    580: {"Kalecgos": 724, "Brutallus": 725, "Felmyst": 726, "Eredar Twins": 727, "M'uru": 728, "Kil'jaeden": 729},
    540: {"Blood Guard Porung": 1935, "Grand Warlock Nethekurse": 1936, "Warbringer O'mrogg": 1937,
          "Warchief Kargath Bladefist": 1938},
    542: {"The Maker": 1922, "Keli'dan the Breaker": 1923, "Broggok": 1924},
    543: {"Omor the Unscarred": 1891, "Vazruden the Herald": 1892, "Watchkeeper Gargolmar": 1893},
    545: {"Hydromancer Thespia": 1942, "Mekgineer Steamrigger": 1943, "Warlord Kalithresh": 1944},
    546: {"Ghaz'an": 1945, "Hungarfen": 1946, "Swamplord Musel'ek": 1947, "The Black Stalker": 1948},
    547: {"Mennu the Betrayer": 1939, "Quagmirran": 1940, "Rokmar the Crackler": 1941},
    552: {"Dalliah the Doomsayer": 1913, "Harbinger Skyriss": 1914, "Wrath-Scryer Soccothrates": 1915,
          "Zereketh the Unbound": 1916},
    553: {"Commander Sarannis": 1925, "High Botanist Freywinn": 1926, "Laj": 1927, "Thorngrin the Tender": 1928,
          "Warp Splinter": 1929},
    554: {"Nethermancer Sepethrea": 1930, "Pathaleon the Calculator": 1931, "Mechano-Lord Capacitus": 1932,
          "Gatewatcher Gyro-Kill": 1933, "Gatewatcher Iron-Hand": 1934},
    555: {"Ambassador Hellmaw": 1908, "Blackheart the Inciter": 1909, "Murmur": 1910, "Grandmaster Vorpil": 1911},
    556: {"Talon King Ikiss": 1902, "Darkweaver Syth": 1903, "Anzu": 1904},
    557: {"Nexus-Prince Shaffar": 1899, "Pandemonius": 1900, "Yor": 250, "Tavarok": 1901},
    558: {"Exarch Maladaar": 1889, "Shirrak the Dead Watcher": 1890},
    560: {"Lieutenant Drake": 1905, "Epoch Hunter": 1906, "Captain Skarloc": 1907},
    269: {"Aeonus": 1919, "Chrono Lord Deja": 1920, "Temporus": 1921},
    585: {"Kael'thas Sunstrider": 1894, "Priestess Delrissa": 1895, "Selin Fireheart": 1897, "Vexallus": 1898},
}
# The end boss of each instance: inside.last marks a KILL step on it (4.5's index fallback).
LAST_BOSS = {532: "Prince Malchezaar", 568: "Zul'jin", 565: "Gruul the Dragonkiller", 544: "Magtheridon",
             548: "Lady Vashj", 550: "Kael'thas Sunstrider", 534: "Archimonde", 564: "Illidan Stormrage",
             580: "Kil'jaeden", 554: "Pathaleon the Calculator", 553: "Warp Splinter", 540: "Warchief Kargath Bladefist",
             555: "Murmur", 552: "Harbinger Skyriss", 269: "Aeonus", 585: "Kael'thas Sunstrider",
             556: "Talon King Ikiss", 560: "Epoch Hunter", 557: "Nexus-Prince Shaffar", 558: "Exarch Maladaar",
             543: "Vazruden the Herald", 542: "Keli'dan the Breaker", 547: "Quagmirran", 546: "The Black Stalker",
             545: "Warlord Kalithresh"}

# British spelling for prose. PROPER are game names the pass must leave alone.
SPELL = {"color": "colour", "colors": "colours", "colored": "coloured", "armor": "armour", "favorite": "favourite",
         "favor": "favour", "behavior": "behaviour", "neighbor": "neighbour", "defense": "defence", "gray": "grey",
         "jewelry": "jewellery", "traveled": "travelled", "canceled": "cancelled", "catalog": "catalogue",
         "mold": "mould", "molds": "moulds"}
# "Key Mold" keeps the three in-game item names whole (Primed, Unfired and Charred Key Mold).
PROPER = ["Eclipsion Armor", "Erratic Behavior", "Enchant Chest - Defense", "Key Mold"]

# Step titles over 60 characters shortened, or reworded where the research title left a number
# without its faction or named a realm stage that a daily hand-in cannot prove.
TITLES = {
    ("ARCATRAZ_KEY", "kill_pathaleon"): "Kill Pathaleon in the Mechanar for the Bottom Shard",
    ("TK_ATTUNEMENT", "trial_strength_trident"): "Trial of Strength: Kalithresh's Trident, heroic Steamvault",
    ("TK_ATTUNEMENT", "trial_strength_essence"): "Trial of Strength: Murmur's Essence, heroic Shadow Labyrinth",
    ("BLACK_TEMPLE_ATTUNEMENT", "ashtongue_corruptors"): "Kill the four Ashtongue Corruptors for the fragments",
    ("BADGES_PHASE_1", "heroic_shattered_halls"): "Heroic Shattered Halls: 4 badges, 5 with the Executioner",
    ("OGRILA_UNLOCK", "wrangle_more_daily"): "Daily: Wrangle More Aether Rays! (350 Ogri'la, 350 Skyguard)",
    # the seven Shattered Sun stage steps are detected as the day's hand-in, not as the realm's stage
    ("SHATTERED_SUN_OFFENSIVE", "stage1_sanctum"): "Daily: Erratic Behavior (Stage 1, the Sanctum)",
    ("SHATTERED_SUN_OFFENSIVE", "stage2_armory"): "Daily: The Battle for the Sun's Reach Armory (Stage 2)",
    ("SHATTERED_SUN_OFFENSIVE", "stage2b_portal"): "Daily: Intercepting the Mana Cells (Stage 2b, the portal)",
    ("SHATTERED_SUN_OFFENSIVE", "stage3_harbor"): "Daily: Intercept the Reinforcements (Stage 3, the harbour)",
    ("SHATTERED_SUN_OFFENSIVE", "stage3b_anvil"): "Daily: Making Ready (Stage 3b, Hauthaa's anvil)",
    ("SHATTERED_SUN_OFFENSIVE", "stage4_alchemy_lab"): "Daily: Discovering Your Roots (Stage 4, the Alchemy Lab)",
    ("SHATTERED_SUN_OFFENSIVE", "stage4b_monument"): "Daily: A Charitable Donation (Stage 4b, the Monument)",
}

# Quest names the research left as a placeholder or an aside (keyed by the emitted guide).
QUEST_NAMES = {
    ("BADGES", "heroic_daily"): "Wanted",
}

# The item a step's quest starts from, where the research giver record is a sentence rather than
# an item record ("Started by the item Orders from Lady Vashj (24367), ...").
ITEM_STARTS = {
    ("HEROIC_COILFANG", "orders_from_lady_vashj"): (24367, "Orders from Lady Vashj"),
}

# KILL npcs that live in another instance than their step's inside.instance: the engine arms the
# combat log only inside KILL_MAPS, so these maps join it (Tempest Keep: The Eye, Hyjal Summit,
# and the bonus and older raid bosses the BADGES rows list).
NPC_MAP = {
    19514: 550, 19516: 550, 18805: 550, 19622: 550,                  # Al'ar, Void Reaver, Solarian, Kael'thas
    17767: 534, 17808: 534, 17888: 534, 17842: 534, 17968: 534,      # Winterchill to Archimonde
    23035: 556, 17301: 540, 18831: 565, 19044: 565, 17257: 544,      # Anzu, the Executioner, Maulgar, Gruul, Magtheridon
    18728: 530, 17711: 530,                                          # Kazzak, Doomwalker
}

# Player prose the research wrote for its auditors (source names, tool fields, notes to the
# builder) or got wrong, rewritten by hand: (emitted guide key, step key or None for the guide,
# field, old, new). Applied before the prose pass to the text the corrections left; a row whose
# old text is missing stops the run, and a row that never meets its step stops it too.
PROSE_FIXES = [
    ("KARAZHAN_ATTUNEMENT", "shadow_lab_key_access", "detail",
     "; Wowhead's Anniversary data attributes it to Ikiss at about one in four, which reflects one player looting the chest per run, so every member who wants a key should open the coffer.",
     "; each player who opens the coffer takes their own key, so every member who wants one should open it."),
    ("GRUUL_MAGTHERIDON", "reach_70", "detail",
     "The wiki text for Gruul's Lair says level 65 may enter while its infobox says 70, so treat 70 as the practical requirement.",
     "Level 70 is the practical requirement for both."),
    ("TK_ATTUNEMENT", "borak_charge", "detail",
     "Return the Third Fragment to Oronok with 10579.", "Return the Third Fragment to Oronok."),
    ("TK_ATTUNEMENT", "trial_mercy", "detail", " (RXP; one wiki page says 80)", ""),
    ("BLACK_TEMPLE_ATTUNEMENT", "akamas_promise", "detail",
     " Two copies of this quest exist in the data (10708 and 11052); Questie blacklists 10708 as a duplicate of 11052 and RXP uses 11052, so accept either as done.",
     ""),
    ("ZUL_AMAN", "enter_zulaman", "detail",
     "Horde fly to Tranquillien, Alliance come up through Zul'Aman's road from the Eastern Plaguelands or take the Thrallmar-free route via the Ghostlands.",
     "Horde fly to Tranquillien; Alliance ride north from the Eastern Plaguelands through the Thalassian Pass into the Ghostlands."),
    ("SUNWELL_PLATEAU", "enter_sunwell", "detail",
     "or by boat from Silvermoon's Sunsail Anchorage.", "or by the flight masters in Ironforge or Silvermoon City."),
    ("HEROIC_COILFANG", "plants_of_zangarmarsh", "detail",
     ", which the wiki records as available until Honored.", ", available until Honored."),
    ("HEROIC_AUCHINDOUN", "outcasts_plight", "detail",
     ", which the wiki records as available until Honored;", ", available until Honored;"),
    ("CAVERNS_OF_TIME_ACCESS", "hero_of_the_brood", "detail",
     "The CMaNGOS TBC database lists this quest as the gate for heroic Black Morass alongside the Key of Time, so finish it before you buy the key.",
     "Heroic Black Morass needs this quest done as well as the Key of Time, so finish it before you buy the key."),
    ("SHADOW_LABYRINTH_KEY", "open_gate", "detail",
     "roughly 35, 65 on the zone map) and go to the southern gate,",
     "roughly 40, 66 on the zone map) and go to the southern gate at about 39.6, 73.8,"),
    ("SHATTERED_HALLS_KEY", "hotter_than_hell", "detail",
     "(Wowhead records more than five hundred spawn points from the far west",
     "(it has more than five hundred spawn points, from the far west"),
    ("SHATTERED_SUN_OFFENSIVE", "stage4b_monument", "detail", " (Questie requiredMaxRep 42000)", ""),
    ("FLYING", None, "summary",
     "and Netherwing Ledge refuses you without Artisan Riding.",
     "and the Netherwing Blood Oath refuses you without Artisan Riding."),
    ("FLYING", "expert_riding", "detail", "and do not exist in this database.", "and do not exist on this client."),
    ("BADGES", "karazhan", "detail", "The wiki calls Karazhan the best badge farm in the game:",
     "Karazhan is the best badge farm in the game:"),
    ("BADGES", "gruul_mag", "detail", " (the wiki's instance total; the split is read as 2 and 3)", ""),
    ("BADGES", "heroic_mgt", "detail",
     "plus the heroic daily's 2 when 11499 is up. Normal mode drops no badges. The heroic key (Magister's Terrace Key) comes from the Hard to Kill and Magisters' Terrace quest chain rather than reputation.",
     "plus the heroic daily's 2 on days its Wanted quest names Magisters' Terrace. Normal mode drops no badges. Heroic Magisters' Terrace has no key: finishing the Hard to Kill chain opens it, not reputation."),
    ("BADGES", "sso_supplies", "detail", "The wiki lists the bag on Intercepting the Mana Cells",
     "The bag comes from Intercepting the Mana Cells"),
    ("BADGES", "talk_geras", "detail",
     "(Questie spawn 50.8, 42.3; the wiki describes him as standing in the central dome and notes he was moved to the upper walkway in patch 2.4, which is the layout the 2.5.x client uses)",
     "(50.8, 42.3)"),
    ("BADGES", "talk_mahduun", "detail",
     "kill a handful of named trash mobs in one of eight dungeons (quests 11364, 11371, 11376, 11383, 11385, 11387, 11389 and, from Phase 5, 11500).",
     "kill a handful of named trash mobs in one of eight dungeons, nine from Phase 5."),
    ("BADGES", "talk_mahduun", "detail",
     " Note that the task brief had the two NPCs the wrong way round; the quest text confirms Zhareem is the heroic (badge) daily and Mah'duun the normal one.",
     ""),
    ("BADGES", "talk_hauthaa", "detail", " (SSO stage 2 complete)", ""),
    ("BADGES", "talk_anwehu", "detail", "(Questie spawn 48.1, 42.9, matching the wiki's 48.1, 42.9)", "(48.1, 42.9)"),
    ("BADGES", "talk_kayri", "detail",
     "She appears at the commencement of SSO phase 3, i.e. as soon as the Sun's Reach Armory (the phase 2 objective) is retaken, the same moment Smith Hauthaa and Anwehu appear; retaking the Harbor (phase 3's objective) is not required.",
     "She appears as soon as the realm retakes the Sun's Reach Armory, the same moment Smith Hauthaa and Anwehu appear; retaking the Harbor is not required."),
    ("BADGES", "talk_shaani", "detail", " (the wiki lists her as stage 4C)", ""),
]
PROSE_FIXES_USED = set()

# The one-line phase sentence at the foot of each course page (guide.phase.note). The research
# first sentences run to 500 characters with ISO dates; these are written from the research notes.
PHASE_NOTE = {
    "KARAZHAN_ATTUNEMENT": "Karazhan has needed The Master's Key since the raid opened in Phase 1 and no Anniversary update has lifted it; one key holder opens the gate for the raid, and a finished attunement is account-wide.",
    "NIGHTBANE_SUMMON": "The Blackened Urn chain has been available since Phase 1 and was never removed; it needs Karazhan access.",
    "GRUUL_MAGTHERIDON": "Neither raid has ever had a gate; since the Zul'Aman update every boss in both also drops Badges of Justice.",
    "SSC_ATTUNEMENT": "Not needed since Phase 3 (27 Aug 2026): Serpentshrine Cavern opens without it. The quests still exist and still count towards Champion of the Naaru.",
    "TK_ATTUNEMENT": "Not needed since Phase 3 (27 Aug 2026): Tempest Keep opens without it. The trials still exist and still count towards Champion of the Naaru.",
    "HYJAL_ATTUNEMENT": "Not needed since Phase 4 (22 Oct 2026): Mount Hyjal opens without it. The Vials of Eternity still exist and still pay Scale of the Sands reputation.",
    "BLACK_TEMPLE_ATTUNEMENT": "Not needed since Phase 4 (22 Oct 2026): the Black Temple opens without it. The chain, the Medallion of Karabor and the Hand of A'dal title remain.",
    "ZUL_AMAN": "Zul'Aman opened with Phase 4 on 22 Oct 2026 with no attunement and a three day lockout.",
    "SUNWELL_PLATEAU": "Sunwell Plateau arrives with Phase 5, Fury of the Sunwell, which has no announced date; no attunement is expected.",
    "HEROIC_HELLFIRE": "The key is needed for the whole of TBC; the standing it costs fell to Honored with the Zul'Aman update.",
    "HEROIC_COILFANG": "The key is needed for the whole of TBC; the standing it costs fell to Honored with the Zul'Aman update.",
    "HEROIC_AUCHINDOUN": "The key is needed for the whole of TBC; the standing it costs fell to Honored with the Zul'Aman update.",
    "HEROIC_TEMPEST_KEEP": "The key is needed for the whole of TBC; the standing it costs fell to Honored with the Zul'Aman update.",
    "HEROIC_CAVERNS_OF_TIME": "The key is needed for the whole of TBC; the standing it costs fell to Honored with the Zul'Aman update.",
    "HEROIC_MAGISTERS_TERRACE": "Magisters' Terrace arrives with Phase 5, Fury of the Sunwell, which has no announced date; Hard to Kill opens its heroic door.",
    "CAVERNS_OF_TIME_ACCESS": "The Old Hillsbrad chain has gated the Black Morass since Phase 1 and is never relaxed in TBC.",
    "SHADOW_LABYRINTH_KEY": "The normal mode key is needed in every phase; the Zul'Aman update changed heroic keys only.",
    "SHATTERED_HALLS_KEY": "The normal mode key is needed in every phase; the Zul'Aman update relaxed the Flamewrought Key, not this door.",
    "ARCATRAZ_KEY": "The normal mode key is needed in every phase; the Zul'Aman update relaxed heroic keys and raid attunements only.",
    "ALDOR_SCRYER_CHOICE": "The choice has been open since Phase 1 and is never removed; Draenei lean Aldor and Blood Elves lean Scryers, but either side can be chosen.",
    "OGRILA_UNLOCK": "Ogri'la opened with Phase 2 on 14 May 2026 and is never removed; every quest needs level 70 and a flying mount.",
    "SKYGUARD_SKETTIS": "Skettis opened with Phase 2 on 14 May 2026 and is never removed; every quest needs level 70 and Expert Riding.",
    "NETHERWING_DAILIES": "Netherwing opened with Phase 3 on 27 Aug 2026 and is never removed; the Blood Oath needs Artisan Riding.",
    "SHATTERED_SUN_OFFENSIVE": "The Isle of Quel'Danas arrives with Phase 5, Fury of the Sunwell, which has no announced date; the realm's stage comes from its own daily quests.",
    "FLYING": "Flying has been available at level 70 since Phase 1; Swift Flight Form for druids came with Phase 2.",
    "BADGES": "Badges of Justice are earned every lockout; where they drop and what G'eras sells change with each phase.",
}

# Steps that are faint reference lines (never counted, never worded), beyond TALK steps and
# MANUAL steps carrying a heroics list.
NOTE_STEPS = {"BADGES": {"no_new_sources", "bank_for_p4", "spend"}, "FLYING": {"reach_tempest_keep"}}

BADGES_TEXT = dict(
    title="Badges of Justice: where they drop and what to buy, phase by phase",
    summary=("Badges of Justice drop from every heroic dungeon boss and from Wind Trader Zhareem's heroic daily in "
             "every phase; from the Zul'Aman update every boss in Karazhan, Zul'Aman, Gruul's Lair, Magtheridon's "
             "Lair, Serpentshrine Cavern and Tempest Keep drops them too, as do Doom Lord Kazzak and Doomwalker, "
             "and the Sunwell phase adds Magisters' Terrace and the Isle of Quel'Danas vendors. This guide never "
             "finishes: it lists what to earn each lockout and what G'eras and the Isle vendors sell this phase."),
    unlocks=("G'eras's catalogue in Shattrath, expanded in Phase 4, and the Sunwell tier gear, gems and PvP pieces "
             "of the Isle of Quel'Danas vendors in Phase 5."),
    spendTitle="Spend: what to buy first this phase",
)

FLYING_TEXT = dict(title="Flying: Expert and Artisan Riding", minLevel=68)

# The FLYING merge: (step key, the research copy that is the base, overrides). None = authored here.
FLYING_STEPS = [
    ("level_70", "FLYING_EPIC", dict(title="Reach level 70, or 68 as a druid", levelByClass={"DRUID": 68})),
    ("learning_to_fly", "FLYING_EPIC", {}),
    ("expert_riding", "FLYING_BASIC", dict(kind="SKILL", skill={"name": "Riding", "skillLineId": 762, "rank": 225},
                                           spellId=34090, title="Train Expert Riding (225) for 800 gold")),
    ("flying_mount", "FLYING_BASIC", dict(title="Buy a 60 percent flying mount, or better")),
    ("flight_form", "FLYING_BASIC", dict(optional=False)),
    ("artisan_riding", "FLYING_EPIC", {}),
    ("epic_flying_mount", "FLYING_EPIC", dict(title="Buy a 280 percent flying mount")),
    ("swift_flight_form", None, dict(
        key="swift_flight_form", kind="SPELL", spellId=40120, optional=False,
        title="Druids: learn Swift Flight Form instead of a 280 mount", phases={"from": 2, "to": None},
        detail=("Druids at level 70 who hold Artisan Riding can learn Swift Flight Form, 280 percent flight, through "
                "the quest chain that begins with Morthis Whisperwing at the Cenarion Refuge and ends with Anzu in "
                "heroic Sethekk Halls; it came with Phase 2 and replaces the epic mount purchase. Artisan Riding is "
                "still required."))),
    ("reach_tempest_keep", "FLYING_BASIC", {}),
]

# ===========================================================================
# Small helpers
# ===========================================================================

def die(msg):
    sys.stderr.write("make_attunements: %s\n" % msg)
    sys.exit(1)


def strip_paren(zone):
    return re.sub(r"\s*\([^)]*\)\s*$", "", zone).strip()


def num(x):
    if isinstance(x, bool):
        return x
    if isinstance(x, float) and x == int(x):
        return int(x)
    return x


def guide_name_prose(text):
    """Research prose names other guides by key ("See the SSC_ATTUNEMENT guide"); the sheet never
    shows an underscore, so a key becomes the navigator name of the guide it merged into."""
    def rep(m):
        key = m.group(0)
        return NAMES.get(MERGED.get(key, key), key)
    keys = sorted(set(list(NAMES) + list(MERGED)), key=len, reverse=True)
    return re.sub(r"\b(" + "|".join(re.escape(k) for k in keys) + r")\b", rep, text)


def british(text):
    marks = {}
    for i, p in enumerate(PROPER):
        token = "\x00%d\x00" % i
        if p in text:
            text = text.replace(p, token)
            marks[token] = p
    def rep(m):
        w = m.group(0)
        out = SPELL[w.lower()]
        return out.capitalize() if w[0].isupper() else out
    text = re.sub(r"\b(" + "|".join(SPELL) + r")\b", rep, text, flags=re.IGNORECASE)
    for token, p in marks.items():
        text = text.replace(token, p)
    return text


ID_PART = re.compile(r"^(?:(?:items?|quests?|npc|object|map|instance|spell|daily) )?\d{4,6}(?:(?:, | or | and )\d{4,6})*$")
INST_PART = re.compile(r"^(?:(?:map|instance) )?(\d{3})$")
# an id after a capitalised name ("Commander Arcus 23452 at", "Champion 29301"); never after a
# lower-case word, where the number is the sentence's own ("quest 10982 at", "instead of 10870")
INLINE_ID = re.compile(r"(\b[A-Z][A-Za-z'!?-]*) \d{5,6}(?=$| at | and | for )")
PAREN = re.compile(r"(\s*)\(([^()]*)\)")


def strip_ids(text):
    """3.8 step 7, the prose is the player's: database ids never reach a sentence. Inside each
    parenthesis a part that is only an id (a quest, item or npc number, labelled or bare, an
    instance or map id) is dropped with its separator, an id lead-in ("11541: free ...") and an id
    after a name ("Commander Arcus 23452 at") lose the number, a parenthesis left with nothing is
    dropped, and one left with a bare number after an id was its subject reads "(350 reputation)".
    Coordinates and amounts are never ids (decimals, or three digits outside INSTANCES)."""
    text = text.replace("(Questie spawn ", "(")

    def one(m):
        lead, body = m.group(1), m.group(2)
        bits = re.split(r"(, |; )", body)
        parts, seps = bits[0::2], [""] + bits[1::2]
        kept, dropped = [], False
        for sep, p in zip(seps, parts):
            q = p
            im = INST_PART.match(q)
            # a bare four-digit number is an id only from 9000 (the 9xxx quests): below it is an
            # amount (1000 reputation, 8000 for Hero of the Brood)
            amount = re.fullmatch(r"\d{4}", q) and int(q) < 9000
            if (ID_PART.match(q) and not amount) or (im and (int(im.group(1)) in INSTANCES or q[0].isalpha())):
                dropped = True
                continue
            q2 = re.sub(r"^\d{4,6}: ", "", q)
            q2 = INLINE_ID.sub(r"\1", q2)
            if q2 != q:
                dropped = True
            kept.append((sep, q2))
        if not dropped:
            return m.group(0)
        if not kept:
            return ""
        out = kept[0][1] + "".join(sep + p for sep, p in kept[1:])
        if re.fullmatch(r"\d{2,4}", out):
            out += " reputation"
        return lead + "(" + out + ")"
    return PAREN.sub(one, text)


def punctuate(text):
    """A quest title that ends in '!', '?' or '...' closes its sentence itself: no '!.' or a
    fifth dot (Don't Stop Now.... is the real title and stays whole)."""
    text = re.sub(r"([!?])\.(?=\s|$)", r"\1", text)
    return re.sub(r"(?<!Don't Stop Now)(?<=[A-Za-z])\.{4}(?=\s|$)", "...", text)


def prose(text):
    if text is None:
        return None
    return punctuate(british(strip_ids(guide_name_prose(text))))


def side_key(k):
    return "SCRYER" if k == "SCRYERS" else k


def is_faction_split(v):
    return isinstance(v, dict) and set(v) == {"A", "H"}


def is_side_split(v):
    return isinstance(v, dict) and set(v) in ({"ALDOR", "SCRYERS"}, {"ALDOR", "SCRYER"})


def split_values(v):
    """The values of a number-or-split field as a list."""
    if isinstance(v, dict):
        return [x for x in v.values() if x is not None]
    return [v] if v is not None else []


# "Ilsa Blusterbrew (Alliance) or Olrokk (Horde, npc 20500 at 29.3, 29.3)"
PAIR_RE = re.compile(r"^(?P<a>.+?) \((?P<ka>Alliance|Aldor)\) or (?P<b>.+?) \((?P<kb>Horde|Scryers), npc (?P<npc>\d+) at (?P<x>[\d.]+), (?P<y>[\d.]+)\)$")
# "Grand Master Dumphry (A) / Grand Master Rohok (H)"; "Crisis at the Sunwell (Aldor) / Duty Calls (Scryers)"
NAME_PAIR_RE = re.compile(r"^(?P<a>.+?) \((?P<ka>A|Aldor)\)(?: /| or) (?P<b>.+?) \((?P<kb>H|Scryers)\)$")


def split_name(text, side_pair=False):
    """A paired name becomes a split: "(A) / (H)" by faction, "(Aldor) / (Scryers)" by side, and a
    bare "X / Y" by side when the step is an Aldor-or-Scryers twin (side_pair), Aldor first as the
    research writes them ("Allegiance to the Aldor / Allegiance to the Scryers")."""
    m = NAME_PAIR_RE.match(text or "")
    if m:
        if m.group("ka") == "A":
            return {"A": m.group("a"), "H": m.group("b")}
        return {"ALDOR": m.group("a"), "SCRYER": m.group("b")}
    if side_pair and text and " / " in text:
        a, b = text.split(" / ", 1)
        return {"ALDOR": a.strip(), "SCRYER": b.strip()}
    return text


# ===========================================================================
# Loading
# ===========================================================================

def load(research_dir):
    bundles = []
    for i in range(7):
        path = os.path.join(research_dir, "research-%d.json" % i)
        if not os.path.exists(path):
            die("missing %s" % path)
        with open(path, encoding="utf8") as f:
            bundles.append(json.load(f))
    return bundles


class Ctx:
    """Everything the handlers and the build share."""

    def __init__(self, bundles):
        self.bundles = bundles
        self.guides = {}          # research key -> guide record (mutable copies)
        self.order = []           # research keys in concatenation order
        self.phases_detail = {}   # research PHASES step key -> detail (corrections applied; report only)
        self.applied = []         # (bundle, index, field, how)
        self.unhandled = []
        self.report = []
        self.dropped = {}         # field -> count
        for b in bundles:
            for g in b["data"]["guides"]:
                g = copy.deepcopy(g)
                self.guides[g["key"]] = g
                self.order.append(g["key"])

    def step(self, gkey, skey):
        g = self.guides[gkey]
        for s in g["steps"]:
            if s["key"] == skey:
                return s
        die("no step %s in %s" % (skey, gkey))

    def steps_everywhere(self, prefix, skey):
        """Every copy of a step key across the guides whose key starts with prefix."""
        out = []
        for k in self.order:
            if k.startswith(prefix):
                for s in self.guides[k]["steps"]:
                    if s["key"] == skey:
                        out.append(s)
        return out

    def insert_after(self, gkey, after_key, step):
        steps = self.guides[gkey]["steps"]
        for i, s in enumerate(steps):
            if s["key"] == after_key:
                steps.insert(i + 1, step)
                return
        die("no step %s in %s to insert after" % (after_key, gkey))

    def drop(self, field, n=1):
        self.dropped[field] = self.dropped.get(field, 0) + n


# ===========================================================================
# Corrections (3.8 step 2): one handler per (guideKey, stepKey, field) that the generic
# verbatim-replacement rule cannot settle. Each handler returns a one-line "how".
# ===========================================================================

def replace_detail(s, old, new):
    if old not in s["detail"]:
        die("detail text not found for replacement: %r" % old[:80])
    s["detail"] = s["detail"].replace(old, new)


def append_detail(s, sentence):
    s["detail"] = s["detail"].rstrip() + " " + sentence.strip()
    if not s["detail"].endswith("."):
        s["detail"] += "."


# The auditors shout a few words in capitals ("NOT in the Aran wing", "near the FRONT"); drawn
# prose does not, so a correction text is calmed before it lands in a detail.
SHOUT = {"NOT": "not", "SIDE ENTRANCE": "side entrance", "FRONT": "front", "START": "start"}


def calm(text):
    for k, v in SHOUT.items():
        text = re.sub(r"\b%s\b" % re.escape(k), v, text)
    return text


def find_step(ctx, gkey, skey):
    g = ctx.guides.get(gkey)
    if not g:
        return None
    for st in g["steps"]:
        if st["key"] == skey:
            return st
    return None


def generic_detail(s, row):
    """3.8 step 2 for a prose row: `from` found -> text replacement; not found -> `to` appended as
    a new sentence. A `to` that ends with a full stop keeps the detail's own stop when the matched
    text already sits before one (no "access.." in the output)."""
    old, new = row["from"], calm(row["to"])
    if old in s["detail"]:
        i = s["detail"].index(old) + len(old)
        # a stop-ended `to` spliced mid-sentence (the original goes on with a lower-case word)
        # loses its stop too, so no ". and" can be emitted
        if new.endswith(".") and (s["detail"][i:i + 1] == "." or re.match(r" [a-z]", s["detail"][i:i + 2])):
            new = new[:-1]
        s["detail"] = s["detail"].replace(old, new, 1)
        return "detail text replaced verbatim"
    text = new
    if text.lower().startswith("add: "):
        text = text[5:]
    append_detail(s, text[0].upper() + text[1:])
    return "detail sentence appended (the from text is not in the detail)"


DUMPHRY = {"npcId": 21209, "name": "Dumphry", "zone": "Hellfire Peninsula", "zoneId": 3483, "x": 51.1, "y": 60.3}
CEYLA = {"npcId": 21402, "name": "Anchorite Ceyla", "zone": "Shadowmoon Valley (Altar of Sha'tar)", "x": 62.6, "y": 28.4}
THELIS = {"npcId": 21955, "name": "Arcanist Thelis", "zone": "Shadowmoon Valley (Sanctum of the Stars)", "x": 56.3, "y": 59.6}
CEYLA_NW = {"npcId": 21402, "name": "Anchorite Ceyla", "zone": "Shadowmoon Valley (Altar of Sha'tar)", "x": 62.4, "y": 28.4}
THELIS_NW = {"npcId": 21955, "name": "Arcanist Thelis", "zone": "Shadowmoon Valley (Sanctum of the Stars)", "x": 56.2, "y": 59.5}
ARCUS = {"npcId": 23452, "name": "Commander Arcus", "zone": "Shadowmoon Valley (Altar of Sha'tar)", "x": 62.4, "y": 29.4}
HOBB = {"npcId": 23434, "name": "Commander Hobb", "zone": "Shadowmoon Valley (Sanctum of the Stars)", "x": 56.5, "y": 58.5}
ARCUS_D = {"npcId": 23452, "name": "Commander Arcus", "zone": "Shadowmoon Valley (Altar of Sha'tar)", "x": 62.4, "y": 29.3}
HOBB_D = {"npcId": 23434, "name": "Commander Hobb", "zone": "Shadowmoon Valley (Sanctum of the Stars)", "x": 56.5, "y": 58.6}
MORGHOR = {"npcId": 23139, "name": "Overlord Mor'ghor", "zone": "Shadowmoon Valley", "x": 66.3, "y": 85.6}
BARTHAMUS = {"npcId": 23433, "name": "Barthamus", "zone": "Shattrath City (Lower City)", "x": 66.6, "y": 16.4}
ADYEN = {"npcId": 18537, "name": "Adyen the Lightwarden", "zone": "Shattrath City (Aldor Rise)", "x": 30.7, "y": 34.6}
DATHRIS = {"npcId": 18594, "name": "Dathris Sunstriker", "zone": "Shattrath City (Scryer's Tier)", "x": 54.6, "y": 80.7}
TYRITH = {"npcId": 24822, "name": "Tyrith", "zone": "Magisters' Terrace (inside the instance)"}


def h_npcids(ids):
    def fn(ctx, row):
        s = ctx.step(row["guideKey"], row["stepKey"])
        s["instance"]["npcIds"] = list(ids)
        return "instance.npcIds = %r" % (ids,)
    return fn


def h_coffer(ctx, row):
    s = ctx.step("KARAZHAN_ATTUNEMENT", "shadow_lab_key_access")
    s["object"] = {"objectId": 187372, "name": "The Talon King's Coffer", "zoneId": 3791}
    append_detail(s, "Since patch 2.3.0 the key is also taken from the Talon King's Coffer beside Ikiss, one per eligible player.")
    unc = ctx.bundles[0]["data"].get("uncertain") or []
    ctx.bundles[0]["data"]["uncertain"] = [u for u in unc if "coffer" not in u.lower()]
    return "object 187372 added, coffer sentence appended, uncertain row dropped"


def h_cot_notes(ctx, row):
    g = ctx.guides["CAVERNS_OF_TIME_ACCESS"]
    g["phase"]["notes"] = g["phase"]["notes"].rstrip() + " " + row["to"].replace("Add: ", "", 1)
    assert set(UNLOCK["HEROIC_CAVERNS_OF_TIME"]["items"]) == {30635, 265849}
    return "guide notes extended (report only); heroic access keys 30635 or 265849 are HEROIC_CAVERNS_OF_TIME's unlock proof"


def h_notes_replace(gkey):
    def fn(ctx, row):
        g = ctx.guides[gkey]
        old, new = row["from"], row["to"]
        if old in (g.get("notes") or ""):
            g["notes"] = g["notes"].replace(old, new)
            return "guide notes replaced (report only)"
        g["notes"] = (g.get("notes") or "").rstrip() + " " + new
        return "guide notes appended (report only)"
    return fn


def h_optional_sunwell_summons(ctx, row):
    s = ctx.step("HEROIC_MAGISTERS_TERRACE", "sunwell_summons")
    s["optional"] = True
    s["altQuestIds"] = sorted(set(s.get("altQuestIds") or []) | {11482})
    s["impliedBy"] = [11488, 11490, 11492]
    return "optional = true, altQuestIds {11482}, impliedBy {11488, 11490, 11492}"


def h_phases_from(n):
    def fn(ctx, row):
        s = ctx.step(row["guideKey"], row["stepKey"])
        s.setdefault("phases", {"from": 1, "to": None})["from"] = n
        return "phases.from = %d" % n
    return fn


def h_append(sentence, strip_prefix="add: "):
    def fn(ctx, row):
        s = ctx.step(row["guideKey"], row["stepKey"])
        text = sentence if sentence else row["to"]
        if strip_prefix and text.lower().startswith(strip_prefix):
            text = text[len(strip_prefix):]
        text = text[0].upper() + text[1:]
        append_detail(s, text)
        return "sentence appended"
    return fn


def h_dumphry(fields):
    def fn(ctx, row):
        s = ctx.step("SHATTERED_HALLS_KEY", row["stepKey"])
        for f in fields:
            s[f]["A"] = dict(DUMPHRY)
        return "%s -> Dumphry 21209 (51.1, 60.3)" % ", ".join(fields)
    return fn


def h_grand_master_detail(ctx, row):
    s = ctx.step("SHATTERED_HALLS_KEY", "grand_master_smith")
    replace_detail(s, "For the Alliance that is the dwarf at the anvil just north-west of the Honor Hold keep (56.8, 63.8); "
                      "the quest calls him Dumphry but the NPC nameplate reads Humphry.",
                   "For the Alliance that is Dumphry, the Grand Master Blacksmith, who stands in the ruined tower outside "
                   "Honor Hold Mine, north-west of Honor Hold along the road (51.1, 60.3). Humphry, the blacksmithing "
                   "trainer at the Honor Hold forge (56.7, 63.6), is a different dwarf and has no part in the chain.")
    return "Dumphry sentence rewritten"


def h_sh_notes(ctx, row):
    g = ctx.guides["SHATTERED_HALLS_KEY"]
    g["notes"] = g["notes"].replace("The quest text names the Alliance smith Dumphry but the NPC (16823) is called Humphry in game.",
                                    "The Alliance smith is NPC 21209 Dumphry at the ruined tower by Honor Hold Mine (51.1, 60.3); "
                                    "16823 Humphry is the unrelated Honor Hold blacksmithing trainer.")
    g["sources"] = [x for x in g.get("sources", [])] + ["https://nether.wowhead.com/tooltip/npc/21209?dataEnv=5&locale=0"]
    return "guide notes and sources updated (report only)"


def h_nazgrel(ctx, row):
    n = 0
    for skey, field in (("entry_into_citadel", "turnIn"), ("grand_master_smith", "giver")):
        rec = ctx.step("SHATTERED_HALLS_KEY", skey)[field]["H"]
        rec["x"], rec["y"] = 55.0, 36.0
        rec.pop("approximate", None)
        n += 1
    unc = ctx.bundles[2]["data"].get("uncertain") or []
    ctx.bundles[2]["data"]["uncertain"] = [u for u in unc if "Nazgrel" not in u]
    return "%d Nazgrel rows at 55.0, 36.0, approximate dropped, uncertain row dropped" % n


def h_level_gates(ctx, row):
    for skey in ("kill_warp_splinter", "kill_pathaleon", "break_into_arcatraz"):
        ctx.step("ARCATRAZ_KEY", skey)["level"] = 70
    unc = ctx.bundles[2]["data"].get("uncertain") or []
    ctx.bundles[2]["data"]["uncertain"] = [u for u in unc if "level" not in u.lower() or "gate" not in u.lower()]
    assert ctx.step("SHATTERED_HALLS_KEY", "level_68")["level"] == 68
    assert ctx.step("ARCATRAZ_KEY", "level_67")["level"] == 67
    return "level = 70 lock on the three How to Break Into the Arcatraz steps; level_68 and level_67 confirmed"


def h_full_triangle(ctx, row):
    s = ctx.step("ARCATRAZ_KEY", "full_triangle")
    s["requiredItem"].pop("alsoAccept", None)
    return "requiredItem.alsoAccept dropped (29026 only)"


def h_special_delivery(ctx, row):
    s = ctx.step("ARCATRAZ_KEY", "special_delivery")
    s["providedItem"] = {"itemId": 29106, "itemName": "Ata'mal Crystal"}
    return "providedItem 29106 Ata'mal Crystal"


def h_phase_notes_za(ctx, row):
    n = 0
    for g in ("SHADOW_LABYRINTH_KEY", "SHATTERED_HALLS_KEY", "ARCATRAZ_KEY"):
        notes = ctx.guides[g]["phase"]["notes"]
        if row["from"] in notes:
            ctx.guides[g]["phase"]["notes"] = notes.replace(row["from"], row["to"])
            n += 1
        elif "Phase 4" in notes:
            ctx.guides[g]["phase"]["notes"] = notes.rstrip() + " " + row["to"] + "."
            n += 1
    return "%d guide phase.notes updated (report only; phase.note is the PHASE_NOTE table)" % n


def h_expert_riding(ctx, row):
    s = ctx.step("FLYING_BASIC", "expert_riding")
    append_detail(s, "No reputation discount applies to Expert or Artisan Riding on this client; faction discounts for "
                     "flying trainers only arrived in patch 3.2.0.")
    unc = ctx.bundles[2]["data"].get("uncertain") or []
    ctx.bundles[2]["data"]["uncertain"] = [u for u in unc if "discount" not in u.lower()]
    return "discount sentence appended, uncertain row dropped"


def h_sh_coords(ctx, row):
    k = ctx.step("SHATTERED_HALLS_KEY", "primed_key_mold")["kill"]
    k["x"], k["y"] = 67.6, 36.2
    n = 1
    for s in ctx.guides["SHATTERED_HALLS_KEY"]["steps"]:
        for f in ("giver", "turnIn"):
            rec = s.get(f)
            if isinstance(rec, dict) and isinstance(rec.get("A"), dict) and rec["A"].get("npcId") == 16819:
                rec["A"]["x"], rec["A"]["y"] = 56.6, 66.7
                n += 1
    return "Smith Gorlunk 67.6, 36.2; %d Danath rows at 56.6, 66.7" % (n - 1)


def h_kalynna_npcids(ctx, row):
    s = ctx.step("NIGHTBANE_SUMMON", "kalynnas_request")
    s["instance"]["npcIds"] = [16807]
    return "instance.npcIds = [16807]"


def h_hand_of_guldan(ctx, row):
    s = ctx.step("TK_ATTUNEMENT", "hand_of_guldan")
    s["giver"] = {"A": {"npcId": 21937, "name": "Earthmender Sophurus", "zone": "Shadowmoon Valley (Wildhammer Stronghold)", "x": 36.4, "y": 57.0},
                  "H": {"npcId": 21938, "name": "Earthmender Splinthoof", "zone": "Shadowmoon Valley (Shadowmoon Village)", "x": 28.5, "y": 26.6}}
    return "giver split A/H"


def h_bt_side(fields):
    def fn(ctx, row):
        s = ctx.step("BLACK_TEMPLE_ATTUNEMENT", row["stepKey"])
        for f in fields:
            s[f] = {"ALDOR": dict(CEYLA), "SCRYER": dict(THELIS)}
        return "%s split ALDOR/SCRYER" % ", ".join(fields)
    return fn


def h_soft(gkey):
    """research-3 #9 and #10: the research rows become recommendations (SOFT); the hard requirements
    the row's `to` names are level 70 (MIN_LEVEL) and, for the Black Temple, the pledge (PREREQS)."""
    def fn(ctx, row):
        assert set(ctx.guides[gkey]["prerequisites"]) <= SOFT[gkey]
        assert MIN_LEVEL.get(gkey) == 70
        hard = PREREQS.get(gkey, [])
        if "pledge" in row["to"]:
            assert any(p["guide"] == "ALDOR_SCRYER_CHOICE" and p["hard"] for p in hard), "pledge row missing from PREREQS"
            return "prerequisites hard = false through the SOFT table; level 70 is MIN_LEVEL; the pledge is appended hard = true through the PREREQS table"
        assert not hard
        return "prerequisites hard = false through the SOFT table; level 70 is MIN_LEVEL"
    return fn


STASIS_FIX = ("Use the Mana-Tombs Stasis Chamber Key (item 32069) on the Mana-Tombs Stasis Chamber near the front "
              "of heroic Mana-Tombs, in the room after Pandemonius on the right; it releases the Consortium "
              "ethereal Ambassador Pax'ivi and no boss kill is needed. Turn in for 5 Badges of Justice and 500 "
              "Consortium reputation. Yor lives in Shaffar's personal chamber and is opened only with Shaffar's "
              "Stasis Chamber Key or The Eye of Haramad. A Thousand Worlds (10973) only becomes available at "
              "Consortium Revered.")
# The three stasis_quest copies word the same error three ways; each copy's wrong clause and
# its replacement. A copy that matches none gets the corrected sentence appended (3.8 step 2).
STASIS_CLAUSES = [
    ("Use the Mana-Tombs Stasis Chamber Key (item 32069) on the chamber behind Shaffar in heroic Mana-Tombs, kill Yor, "
     "and turn in for 5 Badges of Justice and 500 Consortium reputation.", STASIS_FIX),
    ("still pays 5 Badges of Justice once for killing Yor in heroic Mana-Tombs with the Mana-Tombs Stasis Chamber Key "
     "(item 32069).",
     "still pays 5 Badges of Justice once for opening the Mana-Tombs Stasis Chamber near the front of heroic Mana-Tombs "
     "with the Mana-Tombs Stasis Chamber Key (item 32069); it releases Ambassador Pax'ivi and no boss kill is needed."),
    ("pays 5 Badges of Justice once for killing Yor in heroic Mana-Tombs with the Mana-Tombs Stasis Chamber Key "
     "(item 32069).",
     "pays 5 Badges of Justice once for opening the Mana-Tombs Stasis Chamber near the front of heroic Mana-Tombs "
     "with the Mana-Tombs Stasis Chamber Key (item 32069); it releases Ambassador Pax'ivi and no boss kill is needed."),
]


def h_stasis(ctx, row):
    replaced, appended = 0, 0
    for s in ctx.steps_everywhere("BADGES_PHASE_", "stasis_quest"):
        for old, new in STASIS_CLAUSES:
            if old in s["detail"]:
                s["detail"] = s["detail"].replace(old, new, 1)
                replaced += 1
                break
        else:
            append_detail(s, STASIS_FIX)
            appended += 1
        s["instance"]["boss"] = None
        s["instance"]["npcIds"] = []
    return "%d stasis_quest copies rewritten, %d appended; boss and npcIds dropped on all" % (replaced, appended)


def h_sunwell_badges(ctx, row):
    s = ctx.step("BADGES_PHASE_5", "sunwell")
    replace_detail(s, "drop 2 badges each for 12 a week",
                   "drop 2 badges each and Kil'jaeden 3, 12 or 13 a week depending on the source")
    return "per-boss split written as prose (the row's text is an instruction, not a sentence)"


def h_no_new_sources(ctx, row):
    s = ctx.step("BADGES_PHASE_2", "no_new_sources")
    replace_detail(s, "The wiki's badge page mentions the Shartuul's Transporter event in Blade's Edge awarding three "
                      "badges, but the quest id and its Anniversary availability could not be confirmed, so treat it as a "
                      "rumour until seen in game.",
                   "The Shartuul's Transporter event (Ogri'la Honored, Blade's Edge) pays Ogri'la reputation and Depleted "
                   "items only on this client; its three Badges of Justice were added in patch 3.0.2 and do not exist in TBC.")
    return "Shartuul rumour replaced (the row's 'Drop the rumour' instruction not copied into the detail)"


def h_zulaman_split(ctx, row):
    s = ctx.step("BADGES_PHASE_4", "zulaman")
    replace_detail(s, "Nalorakk, Akil'zon, Jan'alai, Halazzi and Hex Lord Malacrass drop 2 badges each and Zul'jin 3, which "
                      "is the instance's 13 total (the per-boss split is derived from that total and the wiki's rule that "
                      "the end boss sometimes drops three).",
                   "Nalorakk drops 1 badge, Akil'zon, Jan'alai and Halazzi 2 each, Hex Lord Malacrass 3 and Zul'jin 3, "
                   "13 in total.")
    s5 = ctx.step("BADGES_PHASE_5", "zulaman")
    replace_detail(s5, "(2 each, 3 from Zul'jin)",
                   "(1 from Nalorakk, 2 each from Akil'zon, Jan'alai and Halazzi, 3 from Hex Lord Malacrass and 3 from Zul'jin)")
    return "both zulaman copies carry the 1, 2, 2, 2, 3, 3 split"


def h_ssc_tk_phase(ctx, row):
    s = ctx.step("BADGES_PHASE_4", "ssc_tk")
    replace_detail(s, "Both are weekly 25-player lockouts and lose their attunement in Phase 4",
                   "Both are weekly 25-player lockouts that lost their attunement at the start of Phase 3 (27 August 2026), "
                   "when the direct skips to Lady Vashj and Kael'thas also opened; Phase 4 removed only the Hyjal and "
                   "Black Temple attunements")
    return "attunement end moved to Phase 3 (joined to the sentence that follows)"


def h_kara_access(ctx, row):
    s = ctx.step("BADGES_PHASE_4", "karazhan")
    replace_detail(s, "Weekly lockout, 10 players, no attunement from Phase 4.",
                   "Weekly lockout, 10 players. Karazhan's gate needs one Master's Key holder in the raid, or a rogue or a "
                   "blacksmith's skeleton key, in every phase; Phase 4 changed nothing about Karazhan access.")
    return "Karazhan access sentence rewritten"


def h_masters_terrace(ctx, row):
    s = ctx.step("NIGHTBANE_SUMMON", "masters_terrace")
    head = "Kamsis gives the journal back to you. "
    assert s["detail"].startswith(head)
    s["detail"] = head + calm(row["to"]).replace("(objective 'Journal Entry Read')", "(objective Journal Entry Read)") \
        .replace("hand the journal to Alturus.", "hand the journal to Archmage Alturus outside.")
    return "route rewritten from the side entrance (the whole detail after the first sentence)"


def h_nightbane_urn(ctx, row):
    s = ctx.step("NIGHTBANE_SUMMON", "nightbane")
    replace_detail(s, row["from"], row["to"].replace("see the masters_terrace step", "see the Master's Terrace step"))
    return "urn sentence replaced; the step reference names the lesson, not its key"


def h_bt_entry_rep(ctx, row):
    s = ctx.step("BLACK_TEMPLE_ATTUNEMENT", "entry_into_black_temple")
    replace_detail(s, row["from"], "Hand in for 150 Ashtongue Deathsworn and 150 Sha'tar reputation.")
    return "reputation figures written without plus signs"


def h_za_quests(ctx, row):
    s = ctx.step("BADGES_PHASE_4", "za_quests")
    replace_detail(s, "it follows X Marks... Your Doom! (11166), which follows A Troll Among Trolls (11165)",
                   "it follows X Marks... Your Doom! (11166), which follows Promises, Promises... (11132), which follows "
                   "Oooh, Shinies! (11130, from Griftah in Shattrath, turned in to Budd)")
    s["relatedQuestIds"] = [11130, 11132, 11166, 11178]
    return "chain rewritten; related quests 11130, 11132, 11166, 11178"


def h_kara_badges(ctx, row):
    n = 0
    for s in ctx.steps_everywhere("BADGES_PHASE_", "karazhan"):
        if "every Karazhan encounter drops 2 Badges of Justice per player" in s["detail"]:
            replace_detail(s, "From Phase 4 every Karazhan encounter drops 2 Badges of Justice per player:",
                           "From Phase 4 every Karazhan encounter drops Badges of Justice, Attumen the Huntsman 1, Prince "
                           "Malchezaar 3 and the other nine 2 each:")
        else:
            replace_detail(s, "2 badges from each of its eleven encounters",
                           "22 badges from its eleven encounters, 1 from Attumen, 3 from Prince Malchezaar and 2 from each of the other nine")
        n += 1
    return "%d karazhan copies: badge split 1, 3 and 2 each" % n


def h_spend_p1(ctx, row):
    s = ctx.step("BADGES_PHASE_1", "spend_p1")
    replace_detail(s, ", Brooch of Deftness)", ")")
    replace_detail(s, "Sapphiron's Wing Bone, Fetish of the Primal Gods, Flametongue Seal, Voodoo Shaker)",
                   "Sapphiron's Wing Bone, Flametongue Seal)")
    return "Brooch of Deftness, Fetish of the Primal Gods and Voodoo Shaker removed from the Phase 1 lists"


def h_sso_supplies(ctx, row):
    s = ctx.step("BADGES_PHASE_5", "sso_supplies")
    s["questIds"] = [11513, 11514, 11520, 11521, 11516, 11877]
    s["questName"] = ("Intercepting the Mana Cells, Maintaining the Sunwell Portal, Discovering Your Roots, Rediscovering "
                      "Your Roots, Blast the Gateway, Sunfury Attack Plans")
    append_detail(s, "Blast the Gateway (11516, Magistrix Seyla at the Throne of Kil'jaeden in Hellfire Peninsula, after "
                     "The Missing Magistrix) and Sunfury Attack Plans (11877, Isle of Quel'Danas) also award Shattered Sun "
                     "Supplies; The Multiphase Survey stopped awarding it in 2.4.2.")
    return "questIds + 11516, 11877; questName and detail extended"


def h_spend_p4(ctx, row):
    s = ctx.step("BADGES_PHASE_4", "spend_p4")
    replace_detail(s, "Blessed Elunite Coverings, Vestments of Hibernation) and 75-badge chests (Chestguard of the Stoic "
                      "Guardian, Hauberk of the Furious Elements)",
                   "Blessed Elunite Coverings) and 75-badge chests (Chestguard of the Stoic Guardian, Hauberk of the "
                   "Furious Elements, Vestments of Hibernation)")
    return "Vestments of Hibernation moved to the chest list"


def h_route_notes(gkey):
    def fn(ctx, row):
        g = ctx.guides[gkey]
        g["phase"]["notes"] = g["phase"]["notes"].replace(row["from"], row["to"])
        return "route phase.notes replaced (report only)"
    return fn


def h_guardian(ctx, row):
    s = ctx.step("OGRILA_UNLOCK", "guardian_monument")
    replace_detail(s, "An Apexis Guardian, an elite crystal golem, stands at each of the Apexis monuments on the plateau "
                      "(around 27.4, 68.6 and 31.8, 63.8, with another far north at 60.0, 9.5). Bring a group, kill one "
                      "and loot the Apexis Guardian's Head.",
                   "Take a group of five to an Apexis Monument (the large relic sites at 27.4, 68.6; 31.8, 63.6; 28.4, "
                   "46.4; 33.5, 51.5; or far north at 60.0, 9.2; 64.4, 10.4 and 69.2, 14.0), spend 35 Apexis Shards and "
                   "win six rounds of the relic game; the Apexis Guardian then spawns. Kill it and loot the Apexis "
                   "Guardian's Head.")
    return "monument game sentence rewritten"


def h_learning_to_fly(ctx, row):
    s = ctx.step("FLYING_EPIC", "learning_to_fly")
    # the research sentence continues ", pointing Alliance players to ..."; the two corrected
    # sentences end with a full stop, so the continuation becomes its own sentence
    replace_detail(s, row["from"] + ", pointing", row["to"] + " It points")
    s["phases"] = {"from": 4, "to": None}
    return "detail replaced (continuation re-joined); phases.from = 4 (A73)"


def h_kill_them_all(ctx, row):
    s = ctx.step("NETHERWING_DAILIES", "kill_them_all")
    s["altQuestIds"] = [11094]
    s["turnIn"] = {"ALDOR": dict(CEYLA_NW), "SCRYER": dict(THELIS_NW)}
    return "turnIn split ALDOR/SCRYER; altQuestIds {11094}"


def h_commander_arcus(ctx, row):
    step = {
        "key": "commander_arcus", "title": "Report to Commander Arcus or Commander Hobb", "kind": "QUEST",
        "questId": 11100, "altQuestIds": [11095], "questName": {"ALDOR": "Commander Arcus", "SCRYER": "Commander Hobb"},
        "giver": {"ALDOR": dict(CEYLA_NW), "SCRYER": dict(THELIS_NW)},
        "turnIn": {"ALDOR": dict(ARCUS), "SCRYER": dict(HOBB)},
        "detail": ("Anchorite Ceyla (Aldor) or Arcanist Thelis (Scryers) sends you on to the officer who commands the "
                   "outpost's defenders: Commander Arcus at the Altar of Sha'tar for the Aldor, Commander Hobb at the "
                   "Sanctum of the Stars for the Scryers. He takes the warning and hands you the Dragonmaw Flare for the "
                   "daily that follows. No reputation."),
        "detectedBy": "", "optional": False,
    }
    ctx.insert_after("NETHERWING_DAILIES", "kill_them_all", step)
    s = ctx.step("NETHERWING_DAILIES", "kill_them_all")
    s.pop("relatedQuestIds", None)
    return "step commander_arcus (11100, alt 11095) inserted after kill_them_all"


def h_deadliest_trap(ctx, row):
    s = ctx.step("NETHERWING_DAILIES", "deadliest_trap_daily")
    s["altQuestIds"] = [11097]
    s["daily"] = True
    s["giver"] = {"ALDOR": dict(ARCUS_D), "SCRYER": dict(HOBB_D)}
    return "giver split ALDOR/SCRYER; altQuestIds {11097}; daily"


def h_lord_illidan(ctx, row):
    step = {
        "key": "lord_illidan", "title": "Lord Illidan Stormrage: survive the scene, find Barthamus", "kind": "QUEST",
        "questId": 11108, "questName": "Lord Illidan Stormrage",
        "giver": dict(MORGHOR), "turnIn": dict(BARTHAMUS),
        "detail": ("Accept Lord Illidan Stormrage from Mor'ghor at Exalted. Illidan lands at the camp, sees through your "
                   "disguise and the Netherwing drakes rise against the Dragonmaw in a scripted scene that ends with "
                   "Mor'ghor dead and you flung into the air; a drake catches you and sets you down. Hand in to Barthamus "
                   "on the ridge above Shattrath's Lower City (66.6, 16.4) for 1000 reputation; the six drake quests all "
                   "require it."),
        "detectedBy": "", "optional": False,
    }
    ctx.insert_after("NETHERWING_DAILIES", "bow_to_highlord", step)
    ctx.step("NETHERWING_DAILIES", "bow_to_highlord").pop("relatedQuestIds", None)
    return "step lord_illidan (11108) inserted after bow_to_highlord"


def h_choose_drake(ctx, row):
    s = ctx.step("NETHERWING_DAILIES", "choose_drake")
    s["altQuestIds"] = [11110, 11111, 11112, 11113, 11114]
    s["giver"] = {"npcId": 23462, "name": "Jorus", "zone": "Shattrath City (Lower City)", "x": 67.9, "y": 17.0}
    s["turnIn"] = {"npcId": 23462, "name": "Jorus", "zone": "Shattrath City (Lower City)", "x": 67.9, "y": 17.0}
    s["questName"] = "Jorus the Cobalt Netherwing Drake"     # 11109's own title; the twins are altQuestIds
    return "altQuestIds 11110 to 11114; giver and turnIn Jorus 23462; questName 11109's own title"


def h_ogrila_friendly(ctx, row):
    """research-5 #2 is an auditor note ('AtlasLoot Friendly tier', 'treat their gate as
    unverified') spliced mid-sentence; the sentence is written whole instead. Honored's own step
    already says Honored adds the Ogre Brews."""
    s = ctx.step("OGRILA_UNLOCK", "friendly")
    if row["from"] not in s["detail"]:
        die("OGRILA_UNLOCK friendly: correction text not found")
    replace_detail(s, row["from"] + " and the tiny thank-you quest A Special Thank You (11091, Chu'a'lor to Jho'nass at 28.1, 58.7, 10 reputation).",
                   "Friendly unlocks Jho'nass's Red and Blue Ogre Brew Special and the small thank-you quest A Special Thank You "
                   "(11091, Chu'a'lor to Jho'nass at 28.1, 58.7, 10 reputation). Jho'nass also sells Crystal Healing and Mana "
                   "Potions for 50 Apexis Shards and 40 silver each.")
    return "Friendly sentence written whole (Ogre Brew Special, the thank-you quest, the potions' price); no source names"


def h_warp_splinter_levels(ctx, row):
    """research-2 #8: the clause through '(or a warlock summon)' is replaced whole, so the summon
    stays beside the flying it qualifies."""
    s = ctx.step("ARCATRAZ_KEY", "kill_warp_splinter")
    replace_detail(s, row["from"] + " (or a warlock summon).",
                   "both instances are level 70 dungeons (the group finder lists the Mechanar from 68 and the Botanica "
                   "from 69) and need flying to reach, or a warlock summon.")
    return "level clause replaced through the warlock summon"


def h_shadow_lab_levels(ctx, row):
    """research-2 #6: one sentence for the tuning and the plan; the original's 'though both are
    tuned for 68 to 70' and its closing 'Plan to do this run ...' said both again."""
    s = ctx.step("SHADOW_LABYRINTH_KEY", "level_65")
    replace_detail(s, row["from"] + ", though both are tuned for 68 to 70.",
                   "Sethekk Halls is tuned for levels 67 to 69 and the Shadow Labyrinth for 70 (the group finder lists "
                   "them from 66 and 69), so plan the run at 68 or later.")
    replace_detail(s, " Plan to do this run around level 68 or later so Ikiss and the Labyrinth are worth the trip.", "")
    return "first sentence written whole; the duplicate closing plan dropped"


def h_consortium_breadcrumb(ctx, row):
    """research-2 #11: the whole original sentence is replaced, so 'talk to Khay'ji directly' is
    said once."""
    s = ctx.step("ARCATRAZ_KEY", "assisting_consortium")
    replace_detail(s, row["from"] + " and talk to Khay'ji directly for Consortium Crystal Collection.",
                   "The breadcrumb only appears once you have completed You're Hired! at Area 52 and either Allegiance to "
                   "the Aldor with Friendly Aldor standing or Allegiance to the Scryers with Friendly Scryers standing; it "
                   "is optional, so when it is not offered, skip it and talk to Khay'ji directly for Consortium Crystal "
                   "Collection.")
    return "breadcrumb sentence replaced whole"


def h_adversarial_blood(ctx, row):
    """research-5 #4: the verbatim replacement, then the research's own Tokens of the Descendants
    sentence folded into it so the repeatable is named once."""
    s = ctx.step("SKYGUARD_SKETTIS", "adversarial_blood")
    generic_detail(s, row)
    replace_detail(s, "Tokens of the Descendants (11074, 350). Tokens of the Descendants (11074, repeatable, 350) lets you "
                      "repeat the summons for more reputation.",
                   "Tokens of the Descendants (11074, 350), which lets you repeat the summons for more reputation.")
    return "detail text replaced verbatim; the repeated Tokens of the Descendants sentence folded in"


def h_egg_hunt(ctx, row):
    s = ctx.step("NETHERWING_DAILIES", "egg_hunt")
    s.pop("daily", None)
    return "one-time: no daily flag (Accepting All Eggs is the repeatable, named in the detail)"


def h_sso_tyrith(ctx, row):
    s = ctx.step("SHATTERED_SUN_OFFENSIVE", "magisters_terrace_chain")
    s["turnIn"] = dict(TYRITH)
    append_detail(s, "Magisters' Terrace is handed in to Tyrith inside the instance; Exarch Larethor only gives it.")
    return "turnIn Tyrith 24822 inside 585"


def h_sso_new_steps(ctx, row):
    for key in ("scryers_scryer", "hard_to_kill"):
        src = copy.deepcopy(ctx.step("HEROIC_MAGISTERS_TERRACE", key))
        src["optional"] = True
        src.pop("phases", None)
        ctx.insert_after("SHATTERED_SUN_OFFENSIVE", "magisters_terrace_chain" if key == "scryers_scryer" else "scryers_scryer", src)
    ctx.step("SHATTERED_SUN_OFFENSIVE", "magisters_terrace_chain").pop("relatedQuestIds", None)
    return "steps scryers_scryer (11490) and hard_to_kill (11492) inserted after magisters_terrace_chain"


def h_sso_intro(ctx, row):
    s = ctx.step("SHATTERED_SUN_OFFENSIVE", "intro_shattrath")
    s["altQuestIds"] = [11482]
    s["giver"] = {"ALDOR": dict(ADYEN), "SCRYER": dict(DATHRIS)}
    s["turnIn"]["y"] = 30.5
    return "giver split ALDOR/SCRYER; Larethor 47.4, 30.5"


def h_sso_rep150(ctx, row):
    s = ctx.step("SHATTERED_SUN_OFFENSIVE", "stage1_sanctum")
    assert "Erratic Behavior (11524" in s["detail"] and "150)" in s["detail"]
    return "detail already says 150 per completion; confirmed"


def h_sso_gating(ctx, row):
    a = ctx.step("SHATTERED_SUN_OFFENSIVE", "stage4b_monument")
    b = ctx.step("SHATTERED_SUN_OFFENSIVE", "title_quest")
    assert "Exalted" in a["detail"] and "Exalted" in b["detail"] and "1000 gold" in b["detail"]
    append_detail(a, "A Charitable Donation is a daily worth 150 reputation and is offered only below Exalted.")
    append_detail(b, "A Magnanimous Benefactor needs Exalted, is one-time, pays 500 reputation and grants the title of the Shattered Sun.")
    return "gating sentences appended to both steps"


def h_sso_phase(ctx, row):
    assert ctx.guides["SHATTERED_SUN_OFFENSIVE"]["phase"]["introduced"] == 5
    return "phase.introduced already 5; confirmed"


def h_phases_detail(ctx, row):
    """The PHASES details are report only (D.PHASES notes are the PHASE_SENTENCES table), but every
    row is still applied: verbatim when found, the Kayri rewrite for its elided row, else appended."""
    s = ctx.step("PHASES", row["stepKey"])
    if row["from"] in s["detail"]:
        s["detail"] = s["detail"].replace(row["from"], row["to"])
        return "PHASES detail replaced (report only)"
    if row["stepKey"] == "phase_5_sunwell" and "new badge vendors on the Isle" in s["detail"]:
        replace_detail(s, "new badge vendors on the Isle", "new vendors on the Isle")
        replace_detail(s, "Kayri for Veteran PvP pieces, Shaani 25950 for uncut epic gems",
                       "Shaani 25950 for uncut epic gems for badges; Kayri in the Sun's Reach Armory sells Veteran's belt, "
                       "bracers and boots for gold and Vindicator's pieces for Tier 6 tokens, not for badges")
        return "PHASES detail rewritten (report only)"
    append_detail(s, row["to"])
    return "PHASES detail appended (report only)"


def h_phases_meta(ctx, row):
    b = ctx.bundles[6]
    g = b["data"]["guides"][0]
    field = row["field"]
    if field == "sources":
        g["sources"] = [row["to"] if x == row["from"] else x for x in g.get("sources", [])]
        return "PHASES sources row replaced (report only)"
    notes = b["data"].get("notes") or ""
    if row["from"] in notes:
        b["data"]["notes"] = notes.replace(row["from"], row["to"])
        return "PHASES notes replaced (report only)"
    b["data"]["notes"] = notes + "\n" + row["to"]
    return "PHASES notes appended (report only)"


HANDLERS = {
    # research-0
    ("KARAZHAN_ATTUNEMENT", "shadow_lab_key_access", "instance.npcIds"): h_npcids([18473]),
    ("KARAZHAN_ATTUNEMENT", "shadow_lab_key_access", "detail / uncertain (coffer object id)"): h_coffer,
    ("CAVERNS_OF_TIME_ACCESS", "(guide-level)", "phase.notes / heroic detection"): h_cot_notes,
    # research-1
    ("HEROIC_CAVERNS_OF_TIME", "(guide notes)", "notes"): h_notes_replace("HEROIC_CAVERNS_OF_TIME"),
    ("HEROIC_MAGISTERS_TERRACE", "sunwell_summons", "optional"): h_optional_sunwell_summons,
    ("HEROIC_TEMPEST_KEEP", "communal_key", "phases.from"): h_phases_from(2),
    ("HEROIC_CAVERNS_OF_TIME", "communal_key", "phases.from"): h_phases_from(2),
    ("HEROIC_COILFANG", "preparing_for_war", "detail"): h_append(None),
    # research-2
    ("SHATTERED_HALLS_KEY", "grand_master_smith", "turnIn.A"): h_dumphry(["turnIn"]),
    ("SHATTERED_HALLS_KEY", "grand_master_smith", "detail"): h_grand_master_detail,
    ("SHATTERED_HALLS_KEY", "smiths_request", "giver.A and turnIn.A"): h_dumphry(["giver", "turnIn"]),
    ("SHATTERED_HALLS_KEY", "hotter_than_hell", "giver.A and turnIn.A"): h_dumphry(["giver", "turnIn"]),
    ("SHATTERED_HALLS_KEY", "(guide)", "notes and sources"): h_sh_notes,
    ("SHATTERED_HALLS_KEY", "entry_into_citadel (turnIn.H) and grand_master_smith (giver.H)", "approximate"): h_nazgrel,
    ("(all four guides)", "(guide)", "uncertain: level gates entry"): h_level_gates,
    ("ARCATRAZ_KEY", "full_triangle", "requiredItem.alsoAccept and detectedBy"): h_full_triangle,
    ("ARCATRAZ_KEY", "special_delivery", "providedItem"): h_special_delivery,
    ("SHADOW_LABYRINTH_KEY (and the phase.notes of SHATTERED_HALLS_KEY, ARCATRAZ_KEY)", "(guide)", "phase.notes"): h_phase_notes_za,
    ("FLYING_BASIC", "expert_riding", "detail and guide-level uncertain"): h_expert_riding,
    ("SHADOW_LABYRINTH_KEY", "level_65", "detail"): h_shadow_lab_levels,
    ("ARCATRAZ_KEY", "kill_warp_splinter", "detail"): h_warp_splinter_levels,
    ("ARCATRAZ_KEY", "assisting_consortium", "detail"): h_consortium_breadcrumb,
    ("SHATTERED_HALLS_KEY", "primed_key_mold / entry_into_citadel", "kill.x,y / turnIn.A.x,y (minor)"): h_sh_coords,
    # research-3
    ("NIGHTBANE_SUMMON", "masters_terrace", "detail"): h_masters_terrace,
    ("NIGHTBANE_SUMMON", "nightbane", "detail"): h_nightbane_urn,
    ("NIGHTBANE_SUMMON", "kalynnas_request", "instance.npcIds"): h_kalynna_npcids,
    ("TK_ATTUNEMENT", "hand_of_guldan", "giver"): h_hand_of_guldan,
    ("BLACK_TEMPLE_ATTUNEMENT", "entry_into_black_temple", "detail"): h_bt_entry_rep,
    ("BLACK_TEMPLE_ATTUNEMENT", "tablets_of_baari", "giver / turnIn"): h_bt_side(["giver", "turnIn"]),
    ("BLACK_TEMPLE_ATTUNEMENT", "oronu_the_elder", "giver / turnIn"): h_bt_side(["giver", "turnIn"]),
    ("BLACK_TEMPLE_ATTUNEMENT", "ashtongue_corruptors", "giver / turnIn"): h_bt_side(["giver", "turnIn"]),
    ("BLACK_TEMPLE_ATTUNEMENT", "wardens_cage", "giver"): h_bt_side(["giver"]),
    ("HYJAL_ATTUNEMENT", "(guide)", "prerequisites"): h_soft("HYJAL_ATTUNEMENT"),
    ("BLACK_TEMPLE_ATTUNEMENT", "(guide)", "prerequisites"): h_soft("BLACK_TEMPLE_ATTUNEMENT"),
    # research-4
    ("BADGES_PHASE_1", "stasis_quest", "detail / instance"): h_stasis,
    ("BADGES_PHASE_4", "za_quests", "detail (chain)"): h_za_quests,
    ("BADGES_PHASE_4", "ssc_tk", "detail"): h_ssc_tk_phase,
    ("BADGES_PHASE_4", "karazhan", "detail"): h_kara_access,
    ("BADGES_PHASE_4", "karazhan", "detail / detectedBy"): h_kara_badges,
    ("BADGES_PHASE_4", "zulaman", "detail"): h_zulaman_split,
    ("BADGES_PHASE_5", "sunwell", "detail"): h_sunwell_badges,
    ("BADGES_PHASE_2", "no_new_sources", "detail"): h_no_new_sources,
    ("BADGES_PHASE_1", "spend_p1", "detail"): h_spend_p1,
    ("BADGES_PHASE_5", "sso_supplies", "questIds / questName / detail"): h_sso_supplies,
    ("BADGES_PHASE_4", "spend_p4", "detail"): h_spend_p4,
    ("BADGES_PHASE_5", "phase.notes", "phase.notes"): h_route_notes("BADGES_PHASE_5"),
    ("BADGES_PHASE_4", "phase.notes", "phase.notes"): h_route_notes("BADGES_PHASE_4"),
    # research-5
    ("OGRILA_UNLOCK", "guardian_monument", "detail"): h_guardian,
    ("OGRILA_UNLOCK", "friendly", "detail"): h_ogrila_friendly,
    ("SKYGUARD_SKETTIS", "adversarial_blood", "detail"): h_adversarial_blood,
    ("FLYING_EPIC", "learning_to_fly", "detail"): h_learning_to_fly,
    ("NETHERWING_DAILIES", "(step for quest 11099 Kill Them All!)", "altQuestIds / turnIn / detectedBy"): h_kill_them_all,
    ("NETHERWING_DAILIES", "(new step between Kill Them All! and The Deadliest Trap Ever Laid)", "steps"): h_commander_arcus,
    ("NETHERWING_DAILIES", "(step for quest 11101 The Deadliest Trap Ever Laid)", "altQuestIds / daily / detail"): h_deadliest_trap,
    ("NETHERWING_DAILIES", "(new step after Bow to the Highlord 11107)", "steps"): h_lord_illidan,
    ("NETHERWING_DAILIES", "(step for quest 11109 drake choice)", "altQuestIds / giver / detectedBy"): h_choose_drake,
    ("NETHERWING_DAILIES", "(step for quest 11049 The Great Netherwing Egg Hunt)", "daily"): h_egg_hunt,
    ("(Sunwell / Shattered Sun guide, key not visible in truncated JSON)", "(step for quest 11488 Magisters' Terrace)", "turnIn"): h_sso_tyrith,
    ("(Sunwell / Shattered Sun guide)", "(new steps after Magisters' Terrace 11488)", "steps"): h_sso_new_steps,
    ("(Sunwell / Shattered Sun guide)", "(step for quest 11481 Crisis at the Sunwell)", "altQuestIds / turnIn zone"): h_sso_intro,
    ("(Sunwell / Shattered Sun guide)", "(step for quest 11524 Erratic Behavior)", "reputation"): h_sso_rep150,
    ("(Sunwell / Shattered Sun guide)", "(steps for 11545 A Charitable Donation and 11549 A Magnanimous Benefactor)", "gating"): h_sso_gating,
    ("(Sunwell / Shattered Sun guide)", "phase", "phase.introduced"): h_sso_phase,
    # research-6 (PHASES: report only, the notes are hand-authored in PHASE_SENTENCES)
    ("PHASES", "phase_5_sunwell", "detail"): h_phases_detail,
    ("PHASES", "(sources)", "sources"): h_phases_meta,
    ("PHASES", "(notes section 8, detection)", "notes"): h_phases_meta,
    ("PHASES", "(notes section 8 item 4 and uncertain)", "notes"): h_phases_meta,
    ("PHASES", "(notes section 3 table)", "notes"): h_phases_meta,
    ("PHASES", "(notes section 7)", "notes"): h_phases_meta,
}


def apply_corrections(ctx):
    """Every verify.corrections row lands: a hand handler keyed on (guideKey, stepKey, field) when
    one exists, else the generic prose rule for a `detail` row on a step that exists (replace when
    `from` is found, append otherwise), else the row is unhandled and the run stops."""
    for bi, b in enumerate(ctx.bundles):
        for ri, row in enumerate(b["verify"]["corrections"]):
            key = (row["guideKey"], row["stepKey"], row["field"])
            handler = HANDLERS.get(key)
            how = None
            if handler is not None:
                how = handler(ctx, row)
            elif row["field"] == "detail":
                if row["guideKey"] == "PHASES":
                    how = h_phases_detail(ctx, row)
                else:
                    s = find_step(ctx, row["guideKey"], row["stepKey"])
                    if s is not None:
                        how = generic_detail(s, row)
            if how is None:
                ctx.unhandled.append((bi, ri, key))
            else:
                ctx.applied.append((bi, ri, key, how))
    if ctx.unhandled:
        for bi, ri, key in ctx.unhandled:
            sys.stderr.write("UNHANDLED correction research-%d #%d %r\n" % (bi, ri, key))
        die("%d correction rows unhandled" % len(ctx.unhandled))
    # Hellfire, Coilfang and Auchindoun communal keys follow the two corrected ones and
    # RULES.communalPouches (false in Phase 1): the pouches are a Phase 2 feature (3.9).
    for g in ("HEROIC_HELLFIRE", "HEROIC_COILFANG", "HEROIC_AUCHINDOUN"):
        ctx.step(g, "communal_key").setdefault("phases", {"from": 1, "to": None})["from"] = 2


# ===========================================================================
# Field mapping (3.8.3): one research step -> one Lua step record
# ===========================================================================

def place_from_record(ctx, rec, role, gkey, skey, kind, inside_instance=None):
    """One research NPC/location record -> one place row (or a faction/side-split pair)."""
    if rec is None:
        return None
    if isinstance(rec, dict) and (is_faction_split(rec) or is_side_split(rec)):
        out = {}
        for k, v in rec.items():
            out[side_key(k)] = place_from_record(ctx, v, role, gkey, skey, kind, inside_instance)
        return out
    if isinstance(rec, str):
        die("string place reference %r on %s:%s" % (rec, gkey, skey))
    if role == "start" and (gkey, skey) in ITEM_STARTS:
        iid, iname = ITEM_STARTS[(gkey, skey)]
        return {"role": "start", "item": iid, "name": iname}
    if (rec.get("name") or "").startswith("Started by"):
        die("start record on %s:%s is a sentence, not an item record: add it to ITEM_STARTS" % (gkey, skey))
    if rec.get("item") is True:
        name = (rec.get("name") or "").split(" (")[0]
        a, h = rec.get("itemId"), rec.get("itemIdHorde")
        if a and h and a != h:
            return {"A": {"role": "start", "item": a, "name": name}, "H": {"role": "start", "item": h, "name": name}}
        return {"role": "start", "item": a or h, "name": name}
    name = rec.get("name")
    m = PAIR_RE.match(name or "")
    if m:
        first = dict(rec)
        first["name"] = m.group("a")
        second = {"npcId": int(m.group("npc")), "name": m.group("b"), "zone": rec.get("zone"),
                  "x": float(m.group("x")), "y": float(m.group("y"))}
        if m.group("ka") == "Alliance":
            return {"A": place_from_record(ctx, first, role, gkey, skey, kind, inside_instance),
                    "H": place_from_record(ctx, second, role, gkey, skey, kind, inside_instance)}
        return {"ALDOR": place_from_record(ctx, first, role, gkey, skey, kind, inside_instance),
                "SCRYER": place_from_record(ctx, second, role, gkey, skey, kind, inside_instance)}
    row = {"role": role, "name": name}
    if rec.get("npcId") is not None:
        row["npc"] = rec["npcId"]
    if rec.get("objectId") is not None:
        row["object"] = rec["objectId"]
    zone = rec.get("zone")
    x, y = rec.get("x"), rec.get("y")
    if zone:
        z = strip_paren(zone)
        if z in MAPS and x is not None and y is not None:
            row["zone"] = z
            row["map"] = MAPS[z]
            row["x"], row["y"] = num(x), num(y)
        elif z in INSTANCE_NAMES:
            row["zone"] = z
            row["instance"] = INSTANCE_NAMES[z]
        elif z in MAPS:
            die("outdoor place without coordinates on %s:%s: %r" % (gkey, skey, zone))
        else:
            die("unmapped zone %r on %s:%s" % (zone, gkey, skey))
    elif rec.get("zoneId") in AREA_TO_INSTANCE:
        row["instance"] = AREA_TO_INSTANCE[rec["zoneId"]]
    elif inside_instance:
        row["instance"] = inside_instance
    elif rec.get("uiMapId") and x is not None:
        row["map"] = rec["uiMapId"]
        row["x"], row["y"] = num(x), num(y)
    else:
        die("place with no zone, instance or item on %s:%s: %r" % (gkey, skey, rec))
    return row


def item_record(s):
    """itemId/item/itemName/count/anyOfItemIds/items -> item = { id, name, count, anyOf }."""
    item = {}
    split = s.get("item")
    if is_faction_split(split):
        item["id"] = {"A": split["A"], "H": split["H"]}
    elif s.get("itemId") is not None:
        item["id"] = s["itemId"]
    if s.get("itemName"):
        item["name"] = s["itemName"]
    if s.get("count") is not None:
        item["count"] = s["count"]
    any_of = s.get("anyOfItemIds")
    if any_of is not None:
        item["anyOf"] = {"A": list(any_of["A"]), "H": list(any_of["H"])} if is_faction_split(any_of) else list(any_of)
    items = s.get("items")
    if isinstance(items, dict):
        a = [r["itemId"] for r in items.get("A", [])]
        h = [r["itemId"] for r in items.get("H", [])]
        anyr = [r["itemId"] for r in items.get("ANY", [])]
        item["anyOf"] = {"A": a + anyr, "H": h + anyr}
        first = (items.get("A") or items.get("H") or items.get("ANY"))[0]
        item.setdefault("name", first["itemName"])
    return item or None


def inside_record(inst, kind, gkey, skey):
    mid = inst["instanceMapId"]
    inside = {"instance": mid, "heroic": bool(inst.get("heroic"))}
    boss = inst.get("boss")
    if boss:
        inside["boss"] = boss
    npcs = inst.get("npcIds") or []
    if npcs:
        inside["npcs"] = list(npcs)
    if kind == "KILL":
        enc = ENCOUNTERS.get(mid, {})
        if boss in enc:
            inside["encounters"] = [enc[boss]]
        if boss and LAST_BOSS.get(mid) == boss:
            inside["last"] = True
    return inside


def convert_step(ctx, gkey, s, guide_instance):
    kind = s["kind"]
    out = {"key": s["key"], "kind": kind, "title": TITLES.get((gkey, s["key"]), s["title"])}
    out["optional"] = bool(s.get("optional"))
    places = []
    inside = None
    inst = s.get("instance")
    if isinstance(inst, dict):
        inside = inside_record(inst, kind, gkey, s["key"])

    # ---- kind-specific identity fields ---------------------------------
    if kind == "QUEST":
        qid = s.get("questId")
        if s.get("quest") is not None:
            q = s["quest"]
            qid = {side_key(k): v for k, v in q.items()}
        if qid is not None:
            out["questId"] = qid
        alts = list(s.get("altQuestIds") or [])
        if s.get("questIdAlt") is not None:
            alts.append(s["questIdAlt"])
        if alts:
            out["altQuestIds"] = alts
        ids = s.get("questIds") or s.get("questAnyOf")
        if ids:
            out["questIds"] = list(ids)
            if s["key"] in ALL_OF.get(MERGED.get(gkey, gkey), set()):
                out["questMode"] = "ALL"
            elif s.get("questId") is None:
                out["questMode"] = "ANY"
            elif s.get("questId") == ids[-1]:
                out["questMode"] = "CHAIN"
            else:
                die("questIds on %s:%s with a questId that is not its last entry" % (gkey, s["key"]))
        if s.get("questName"):
            side_pair = is_side_split(qid) or (gkey == "ALDOR_SCRYER_CHOICE" and bool(alts))
            out["questName"] = split_name(s["questName"], side_pair) if isinstance(s["questName"], str) else s["questName"]
        if s.get("choice"):
            out["choice"] = [{"questId": c["questId"], "name": c["questName"], "factionId": c["factionId"]} for c in s["choice"]]
        if s.get("itemId") is not None:
            out["questItem"] = {"id": s["itemId"], "name": s.get("itemName"), "count": s.get("count")}
        if isinstance(s.get("items"), list):
            out["questItems"] = [{"id": r["itemId"], "name": r["itemName"]} for r in s["items"]]
        if s.get("anyOfItemIds") is not None:
            out["item"] = {"anyOf": list(s["anyOfItemIds"])}
        # 3.8.3 maps factionId/standing to needsStanding on an ITEM step only: on a QUEST step it is
        # the research's detection hint (Hyjal turn_in_vials), not a requirement of the quest
        if s.get("factionId") is not None:
            ctx.drop("factionId (a QUEST step's detection hint)")
        if s.get("daily"):
            out["daily"] = True
        if s.get("level") is not None:
            out["level"] = s["level"]
    elif kind == "ITEM":
        out["item"] = item_record(s)
        if s.get("questId") is not None:
            out["questId"] = s["questId"]
            if s.get("questName"):
                out["questName"] = s["questName"]
        if s.get("factionId") is not None:
            fid = s["factionId"]
            out["needsStanding"] = {"factionId": fid, "standing": s["standing"], "factionName": FACTIONS[fid]}
        if s.get("pouch"):
            p = s["pouch"]
            pitem = {"A": p["A"], "H": p["H"]} if "A" in p else p.get("itemId")
            out["pouch"] = {"item": pitem, "name": p.get("name"), "cost": p.get("cost"), "standing": 7}
        if s.get("skill"):
            ctx.drop("skill (on a non-SKILL step)")
    elif kind == "REP":
        fid = s["factionId"]
        out["factionId"] = {"A": fid["A"], "H": fid["H"]} if is_faction_split(fid) else fid
        for f in split_values(fid):
            if f not in FACTIONS:
                die("REP step %s:%s names faction %r, missing from FACTIONS" % (gkey, s["key"], f))
        out["factionName"] = {"A": FACTIONS[fid["A"]], "H": FACTIONS[fid["H"]]} if is_faction_split(fid) else FACTIONS[fid]
        out["standing"] = s["standing"]
        if s.get("anyOfItemIds") is not None:
            out["item"] = {"anyOf": list(s["anyOfItemIds"])}
    elif kind == "KILL":
        if s.get("questId") is not None:
            out["questId"] = s["questId"]
            if s.get("questName"):
                out["questName"] = s["questName"]
        if s.get("itemId") is not None:
            out["item"] = {"id": s["itemId"], "name": s.get("itemName"), "count": s.get("count")}
    elif kind == "LEVEL":
        out["level"] = s["level"]
    elif kind == "SPELL":
        out["spellId"] = s["spellId"]
        if s.get("spellName"):
            ctx.drop("spellName")
    elif kind == "SKILL":
        sk = s["skill"]
        out["skill"] = {"name": sk["name"], "line": sk["skillLineId"], "rank": sk["rank"]}
        if s.get("spellId") is not None:
            out["spellId"] = s["spellId"]
    elif kind == "MANUAL":
        if isinstance(s.get("instances"), list):
            out["list"] = [{"name": r["name"], "instance": r["instanceMapId"], "badges": r["badges"], "bonus": r.get("bonus")}
                           for r in s["instances"]]
            out["note"] = True
        if inside:
            out["auto"] = {"enteredInstance": inside["instance"], "heroic": inside["heroic"]}
        elif guide_instance and (s["key"].startswith("open_") or s["key"].startswith("enter_")):
            out["auto"] = {"enteredInstance": guide_instance, "heroic": False}
        elif s["key"] in AUTO:
            out["auto"] = dict(AUTO[s["key"]])
    elif kind == "TALK":
        out["note"] = True
    else:
        die("unknown kind %r on %s:%s" % (kind, gkey, s["key"]))

    if kind != "QUEST" and s.get("level") is not None and kind != "LEVEL":
        out["level"] = s["level"]
    if kind != "QUEST" and s.get("daily"):
        out["daily"] = True

    # ---- shared fields ----------------------------------------------------
    if s.get("cost"):
        out["cost"] = s["cost"]
    ri = s.get("requiredItem")
    if ri:
        needs = {"id": ri["itemId"], "name": ri.get("itemName"), "count": ri.get("count")}
        if ri.get("alsoAccept"):
            needs["anyOf"] = list(ri["alsoAccept"])
        out["needs"] = needs
    if s.get("providedItem"):
        out["provided"] = {"id": s["providedItem"]["itemId"], "name": s["providedItem"]["itemName"]}
    if s.get("relatedDailyIds") or s.get("relatedQuestIds"):
        out["related"] = {}
        if s.get("relatedDailyIds"):
            out["related"]["dailies"] = list(s["relatedDailyIds"])
        if s.get("relatedQuestIds"):
            out["related"]["quests"] = list(s["relatedQuestIds"])
    if s.get("phases"):
        out["phases"] = {"from": s["phases"]["from"], "to": s["phases"].get("to") if s["phases"].get("to") is not None else False}
    if s.get("impliedBy"):
        out["impliedBy"] = list(s["impliedBy"])
    for f in ("materials", "mobs", "detectedBy"):
        if s.get(f) is not None:
            ctx.drop(f)
    if inside:
        out["inside"] = inside

    # ---- places -------------------------------------------------------------
    give_role = {"QUEST": "start", "KILL": "start", "ITEM": "vendor", "SKILL": "trainer", "SPELL": "trainer", "TALK": "vendor"}.get(kind, "start")
    turn_role = {"QUEST": "turnin", "KILL": "turnin", "ITEM": "vendor"}.get(kind, "turnin")
    if kind == "ITEM" and s.get("questId") is not None:
        give_role, turn_role = "start", "turnin"
    inside_id = inside["instance"] if inside else None
    if s.get("giver") is not None:
        places.append(place_from_record(ctx, s["giver"], give_role, gkey, s["key"], kind, inside_id))
    if s.get("turnIn") is not None:
        turn = s["turnIn"]
        if turn == "giver":            # 3.8.3: the string reference copies the giver record
            turn = s.get("giver")
        r = place_from_record(ctx, turn, turn_role, gkey, s["key"], kind, inside_id)
        if r is not None:
            places.append(r)
    if s.get("kill"):
        k = s["kill"]
        places.append(place_from_record(ctx, {"npcId": k["npcId"], "name": k["name"], "zone": k["zone"], "x": k["x"], "y": k["y"]},
                                        "kill", gkey, s["key"], kind))
    if s.get("location"):
        loc = s["location"]
        places.append(place_from_record(ctx, {"name": loc.get("subzone") or strip_paren(loc["zone"]), "zone": loc["zone"],
                                              "x": loc["x"], "y": loc["y"]}, "spot", gkey, s["key"], kind))
    door_instance = None
    if s.get("entrance"):
        e = s["entrance"]
        door_instance = inside_id or guide_instance
        if not door_instance:
            die("entrance with no instance on %s:%s" % (gkey, s["key"]))
        places.append({"role": "door", "name": INSTANCES[door_instance], "zone": strip_paren(e["zone"]), "map": e["uiMapId"],
                       "x": num(e["x"]), "y": num(e["y"]), "instance": door_instance})
    if inside and door_instance != inside["instance"]:
        places.append({"role": "inside", "name": INSTANCES[inside["instance"]], "instance": inside["instance"]})
    if s.get("object"):
        o = s["object"]
        places.append({"role": "object", "name": o["name"], "object": o["objectId"], "instance": AREA_TO_INSTANCE[o["zoneId"]]})
    # de-duplicate identical rows (giver == turnIn at the same NPC keeps both roles; identical rows do not repeat)
    seen, uniq = [], []
    for p in places:
        if p is None:
            continue
        sig = json.dumps(p, sort_keys=True)
        if sig in seen:
            continue
        seen.append(sig)
        uniq.append(p)
    if uniq:
        out["places"] = uniq
    out["detail"] = s.get("detail")
    return out


# ===========================================================================
# Guides (3.8 steps 3 to 6)
# ===========================================================================

def window_of(phase):
    ru = phase.get("requiredUntil")
    return {"from": phase["introduced"], "to": (ru - 1) if ru else False}


def union_window(a, b):
    to = False if (a["to"] is False or b["to"] is False) else max(a["to"], b["to"])
    return {"from": min(a["from"], b["from"]), "to": to}


def first_sentence(text):
    m = re.match(r"(.+?\.)(\s+[A-Z]|$)", text or "", re.S)
    return m.group(1) if m else (text or "")


def quest_ids_of(step):
    ids = []
    if step.get("questId") is not None:
        ids += split_values(step["questId"])
    ids += step.get("altQuestIds") or []
    return ids


def unlock_for(ctx, key, g):
    """3.6: SHATTERED_HALLS_KEY's unlock proof is item 28395 only when the research turn-in step
    carries that id; otherwise the guide has no unlock."""
    unlock = copy.deepcopy(UNLOCK.get(key))
    if key == "SHATTERED_HALLS_KEY" and unlock:
        held = [s["key"] for s in g["steps"]
                if s.get("itemId") == 28395 or (s.get("providedItem") or {}).get("itemId") == 28395]
        if held:
            ctx.report.append("SHATTERED_HALLS_KEY unlock 28395 confirmed by research step %s" % held[0])
        else:
            ctx.report.append("SHATTERED_HALLS_KEY: 28395 absent from the research steps; no unlock emitted")
            unlock = None
    return unlock


def build_plain_guide(ctx, gkey):
    g = ctx.guides[gkey]
    key = gkey
    inst = GUIDE_INSTANCE.get(key)
    steps = [convert_step(ctx, gkey, s, inst) for s in g["steps"]]
    return finish_guide(ctx, key, g, steps, inst)


def finish_guide(ctx, key, g, steps, inst, extra=None):
    extra = extra or {}
    phase = {"introduced": g["phase"]["introduced"],
             "requiredUntil": g["phase"].get("requiredUntil") if g["phase"].get("requiredUntil") is not None else False}
    phase["note"] = PHASE_NOTE.get(key) or first_sentence(g["phase"].get("notes"))
    window = window_of(g["phase"])
    out = {
        "key": key, "name": NAMES[key], "title": extra.get("title", g["title"]), "category": g["category"],
        "order": None, "faction": g.get("faction") or "BOTH", "gate": GATES.get(key), "phase": phase,
        "unlock": unlock_for(ctx, key, g), "accountWide": key in ACCOUNT_WIDE, "minLevel": None,
        "instance": inst, "recurring": bool(extra.get("recurring")), "prerequisites": [],
        "alternatives": None, "summary": extra.get("summary", g.get("summary")), "unlocks": extra.get("unlocks", g.get("unlocks")),
        "steps": steps,
    }
    # prerequisites: MERGED, deduplicated, never the guide itself, SOFT -> hard = false; then the
    # PREREQS hand rows appended under the same dedup and never-self rule (3.8.6)
    seen = set()
    for p in g.get("prerequisites") or []:
        t = MERGED.get(p, p)
        if t == key or t in seen:
            continue
        seen.add(t)
        out["prerequisites"].append({"guide": t, "hard": p not in SOFT.get(key, set())})
    for p in PREREQS.get(key, []):
        t = MERGED.get(p["guide"], p["guide"])
        if t == key or t in seen:
            continue
        seen.add(t)
        out["prerequisites"].append({"guide": t, "hard": bool(p["hard"])})
    # steps: optional, note, classes, level, daily, full, weekly, phases
    skeys = {s["key"] for s in steps}
    for s in steps:
        if s["key"] in OPTIONAL.get(key, set()):
            s["optional"] = True
        if s["key"] in NOTE_STEPS.get(key, set()):
            s["note"] = True
        if s["key"] in CLASSES.get(key, {}):
            s["classes"] = list(CLASSES[key][s["key"]])
        if s["key"] in LEVEL.get(key, {}):
            s["level"] = LEVEL[key][s["key"]]
        if s["key"] in DAILY.get(key, set()):
            s["daily"] = True
        if s["kind"] == "KILL" and s["key"] in FULL_CLEAR.get(key, set()):
            s["inside"]["full"] = True
            enc = ENCOUNTERS.get(s["inside"]["instance"], {})
            if enc:
                s["inside"]["encounters"] = sorted(enc.values())
        if not s.get("phases"):
            s["phases"] = dict(window)
    # HEROIC key guides: the 3.9 example emits buy_key with anyOf = the key or its Communal twin, so a
    # Communal holder reads the step Done in its own right (the research carries no anyOfItemIds here)
    if g.get("category") == "HEROIC":
        by_key = {s["key"]: s for s in steps}
        buy, communal = by_key.get("buy_key"), by_key.get("communal_key")
        if buy and communal and buy.get("item") and not buy["item"].get("anyOf"):
            kid, cid = buy["item"].get("id"), (communal.get("item") or {}).get("id")
            if is_faction_split(kid) and is_faction_split(cid):
                buy["item"]["anyOf"] = {"A": [kid["A"], cid["A"]], "H": [kid["H"], cid["H"]]}
            elif isinstance(kid, int) and isinstance(cid, int):
                buy["item"]["anyOf"] = [kid, cid]
    # the same questId on two QUEST steps: the earlier one is the accept step
    qsteps = [s for s in steps if s["kind"] == "QUEST" and s.get("questId") is not None]
    for i, a in enumerate(qsteps):
        for b in qsteps[i + 1:]:
            if a["questId"] == b["questId"]:
                a["accept"] = True
    # alternatives: grouped steps are counted (not optional)
    alts = ALTERNATIVES.get(key)
    if alts:
        out["alternatives"] = copy.deepcopy(alts)
        for goal in alts.values():
            for grp in goal["groups"]:
                for sk in grp:
                    if sk not in skeys:
                        die("alternatives step %s missing in %s" % (sk, key))
                    for s in steps:
                        if s["key"] == sk:
                            s["optional"] = False
    # consumedBy
    for sk, target in CONSUMED.get(key, {}).items():
        if sk not in skeys or target not in skeys:
            die("CONSUMED row %s -> %s not in %s" % (sk, target, key))
        for s in steps:
            if s["key"] == sk:
                s["consumedBy"] = target
    # impliedBy on the linear guides
    if key in IMPLIED:
        sib = {}
        for group in SIBLINGS.get(key, []):
            for q in group:
                sib[q] = set(group)
        qsteps = [s for s in steps if s["kind"] == "QUEST"]
        for i, s in enumerate(qsteps):
            if s.get("accept"):
                continue
            own = set(quest_ids_of(s))
            exclude = set()
            for q in own:
                exclude |= sib.get(q, set())
            later = []
            for t in qsteps[i + 1:]:
                for q in quest_ids_of(t):
                    if q not in exclude and q not in own and q not in later:
                        later.append(q)
            if later:
                s["impliedBy"] = later
    # minLevel: the LEVEL step, else the highest QUEST level, else MIN_LEVEL
    lvl = None
    for s in steps:
        if s["kind"] == "LEVEL":
            vals = [s["level"]] + list((s.get("levelByClass") or {}).values())
            lvl = min(vals)
    if lvl is None:
        qlv = [s["level"] for s in steps if s["kind"] == "QUEST" and s.get("level")]
        if qlv:
            lvl = max(qlv)
    if lvl is None:
        lvl = MIN_LEVEL.get(key)
    if extra.get("minLevel"):
        lvl = extra["minLevel"]
    out["minLevel"] = lvl
    # hand-written prose and quest names, before the prose pass
    by_step = {s["key"]: s for s in steps}
    for i, (gk, sk, field, old, new) in enumerate(PROSE_FIXES):
        if gk != key:
            continue
        rec = out if sk is None else by_step.get(sk)
        if rec is None:
            die("PROSE_FIXES row %d names %s:%s, which is not a step" % (i, gk, sk))
        if not rec.get(field) or old not in rec[field]:
            die("PROSE_FIXES row %d: text not found in %s:%s %s: %r" % (i, gk, sk, field, old[:80]))
        rec[field] = rec[field].replace(old, new, 1)
        PROSE_FIXES_USED.add(i)
    for (gk, sk), name in QUEST_NAMES.items():
        if gk == key:
            if sk not in by_step or not by_step[sk].get("questName"):
                die("QUEST_NAMES names %s:%s, which has no questName" % (gk, sk))
            by_step[sk]["questName"] = name
    # prose pass
    for s in steps:
        s["title"] = prose(s["title"])
        s["detail"] = prose(s["detail"])
        if s.get("detailByPhase"):
            s["detailByPhase"] = {k: prose(v) for k, v in s["detailByPhase"].items()}
    out["summary"] = prose(out["summary"])
    out["unlocks"] = prose(out["unlocks"])
    out["phase"]["note"] = prose(out["phase"]["note"])
    return out


def build_badges(ctx):
    routes = ["BADGES_PHASE_%d" % n for n in range(1, 6)]
    merged = {}
    order = []
    spend = None
    for rk in routes:
        g = ctx.guides[rk]
        window = window_of(g["phase"])
        n = g["phase"]["introduced"]
        for rs in g["steps"]:
            s = convert_step(ctx, rk, rs, None)
            own = s.get("phases") or dict(window)
            if rs["key"].startswith("spend_p"):
                if spend is None:
                    spend = {"key": "spend", "kind": "MANUAL", "title": BADGES_TEXT["spendTitle"], "optional": False, "note": True,
                             "section": "SPEND", "phases": dict(own), "detailByPhase": {}, "detail": None}
                else:
                    spend["phases"] = union_window(spend["phases"], own)
                spend["detailByPhase"][n] = s["detail"]
                continue
            if s["key"] not in merged:
                s["phases"] = dict(own)
                merged[s["key"]] = s
                order.append(s["key"])
                if s["key"] == "heroics_overview":
                    s["detailByPhase"] = {n: s["detail"]}
            else:
                m = merged[s["key"]]
                m["phases"] = union_window(m["phases"], own)
                if s["key"] == "heroics_overview":
                    # each route words its own lap (Phase 5 adds Magisters' Terrace): the prose goes by
                    # phase and a row first listed by a later route carries that route's phase
                    m["detailByPhase"][n] = s["detail"]
                    have = {r["instance"] for r in m["list"]}
                    for r in s.get("list") or []:
                        if r["instance"] not in have:
                            row = dict(r)
                            row["from"] = n
                            m["list"].append(row)
                if s.get("questIds"):
                    ids = list(m.get("questIds") or [])
                    for q in s["questIds"]:
                        if q not in ids:
                            ids.append(q)
                    m["questIds"] = ids
                    m.setdefault("questMode", s.get("questMode"))
                if not s["optional"]:
                    m["optional"] = False
    steps = [merged[k] for k in order]
    for s in steps:
        if s["kind"] == "KILL":
            s["weekly"] = True
        if s.get("detailByPhase") and s["key"] != "spend":
            # detailByPhase ONLY, as the spend note: the engine prefers step.detail when present
            s["detail"] = None
    # The spend step carries detailByPhase ONLY: the engine prefers step.detail when present, so
    # a detail copy would pin the page to the Phase 1 advice in every phase.
    steps.append(spend)
    vendors = ctx.guides["BADGE_VENDORS"]
    for rs in vendors["steps"]:
        s = convert_step(ctx, "BADGE_VENDORS", rs, None)
        s["note"] = True
        s["section"] = "SPEND"
        steps.append(s)
    g = {"title": BADGES_TEXT["title"], "category": "BADGES", "faction": "BOTH",
         "phase": {"introduced": 1, "requiredUntil": None, "notes": ""}, "prerequisites": [],
         "summary": BADGES_TEXT["summary"], "unlocks": BADGES_TEXT["unlocks"]}
    return finish_guide(ctx, "BADGES", g, steps, None, extra={"recurring": True})


def build_flying(ctx):
    basic, epic = ctx.guides["FLYING_BASIC"], ctx.guides["FLYING_EPIC"]
    by = {"FLYING_BASIC": {s["key"]: s for s in basic["steps"]}, "FLYING_EPIC": {s["key"]: s for s in epic["steps"]}}
    steps = []
    for key, src, over in FLYING_STEPS:
        if src is None:
            rs = dict(over)
        else:
            rs = copy.deepcopy(by[src][key])
            for k, v in over.items():
                rs[k] = v
        s = convert_step(ctx, src or "FLYING", rs, None)
        if key == "flying_mount":
            s["item"]["anyOf"] = {"A": MOUNTS["basic"]["A"] + MOUNTS["basic"]["ANY"] + MOUNTS["epic"]["A"] + MOUNTS["epic"]["ANY"],
                                  "H": MOUNTS["basic"]["H"] + MOUNTS["basic"]["ANY"] + MOUNTS["epic"]["H"] + MOUNTS["epic"]["ANY"]}
            s["item"].pop("id", None)
            s["item"]["name"] = "a flying mount"     # not the first research row's Alliance gryphon
            s["optional"] = False       # FLYING_BASIC's counted copy wins (3.8.5)
        if key == "epic_flying_mount":
            s["item"]["anyOf"] = {"A": MOUNTS["epic"]["A"] + MOUNTS["epic"]["ANY"], "H": MOUNTS["epic"]["H"] + MOUNTS["epic"]["ANY"]}
            s["item"].pop("id", None)
            s["item"]["name"] = "a 280 percent flying mount"
        if key == "level_70":
            s["levelByClass"] = dict(over["levelByClass"])
        steps.append(s)
    g = {"title": FLYING_TEXT["title"], "category": "FLYING", "faction": "BOTH",
         "phase": {"introduced": 1, "requiredUntil": None, "notes": epic["phase"]["notes"]}, "prerequisites": [],
         "summary": epic["summary"], "unlocks": epic["unlocks"]}
    return finish_guide(ctx, "FLYING", g, steps, None, extra={"minLevel": FLYING_TEXT["minLevel"]})


def build_guides(ctx):
    guides = []
    done_merged = set()
    for k in ctx.order:
        if k in DROPPED_GUIDES:
            ctx.phases_detail = {s["key"]: s["detail"] for s in ctx.guides[k]["steps"]}
            continue
        if k in MERGED:
            t = MERGED[k]
            if t in done_merged:
                continue
            done_merged.add(t)
            guides.append(build_badges(ctx) if t == "BADGES" else build_flying(ctx))
            continue
        guides.append(build_plain_guide(ctx, k))
    # order within a category: data order x 10
    counters = {}
    for g in guides:
        counters[g["category"]] = counters.get(g["category"], 0) + 1
        g["order"] = counters[g["category"]] * 10
    cat_rank = {k: i for i, (k, _) in enumerate(CATEGORIES)}
    guides.sort(key=lambda g: (cat_rank[g["category"]], g["order"]))
    return guides


def build_top(guides):
    phases = []
    for p in PHASES:
        row = {"n": p["n"], "short": p["short"], "name": p["name"], "blizzard": p["blizzard"], "since": p["since"]}
        if p.get("raidsOpen"):
            row["raidsOpen"] = p["raidsOpen"]
        row["notes"] = PHASE_SENTENCES[p["n"]]["notes"]
        phases.append(row)
    rules = {}
    for n, r in RULE_ROWS.items():
        rules[n] = {
            "heroicKeyStanding": r["heroicKeyStanding"], "communalPouches": r["communalPouches"],
            "heroicTuning": r["heroicTuning"], "vendorStock": r["vendorStock"],
            "attunementRequired": {k: (k in r["required"]) for k in GATE_KEYS},
            "raidsOpen": list(r["raidsOpen"]),
            "badgeSources": {k: (k in r["badges"]) for k in BADGE_KEYS},
            "live": {k: (k in r["live"]) for k in LIVE_KEYS},
            "assumed": list(r["assumed"]),
            "sentences": list(PHASE_SENTENCES[n]["sentences"]),
        }
    kill_maps = set()
    for g in guides:
        for s in g["steps"]:
            if s["kind"] == "KILL" and s.get("inside"):
                kill_maps.add(s["inside"]["instance"])
                for npc in s["inside"].get("npcs") or []:
                    if npc in NPC_MAP:
                        kill_maps.add(NPC_MAP[npc])
    kill_maps.add(530)
    return {"BUILD": BUILD, "SOURCE": SOURCE, "PHASES": phases, "RULES": rules, "EVIDENCE": EVIDENCE,
            "CATEGORIES": [{"key": k, "label": l} for k, l in CATEGORIES], "INSTANCES": INSTANCES, "MAPS": MAPS,
            "KILL_MAPS": {m: True for m in sorted(kill_maps)}}


# ===========================================================================
# Invariants (3.8 step 8)
# ===========================================================================

def walk_strings(v, path, out):
    if isinstance(v, str):
        out.append((path, v))
    elif isinstance(v, dict):
        for k, x in v.items():
            walk_strings(x, path + "." + str(k), out)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            walk_strings(x, path + "[%d]" % i, out)


REAL_BRACKET_TITLES = {"Grim(oire) Business"}       # quest titles whose brackets are the game's own
PROSE_BANNED = [
    (re.compile(r"RXP|Wowhead|CMaNGOS|AtlasLoot|Questie|\b[Ww]iki|database|in the data|task brief|\bunverified|requiredMaxRep"), "a research source or note"),
    (re.compile(r"\b[a-z]+[A-Z][A-Za-z]*"), "a camelCase token"),
    (re.compile(r"Magister's"), "Magister's for Magisters'"),
    (re.compile(r"[!?]\.(?=\s|$)|(?<!Don't Stop Now)\.{4}"), "a doubled stop"),
    (re.compile(r"(?<!\.\.\.)\. [a-z]"), "a sentence starting lower case"),
    (re.compile(r"\((?:\d{4,6}|(?:instance|map|npc|object) \d+)[,):]|, \d{5,6}\)"), "a database id in brackets"),
    (re.compile(r"Thrallmar-free|Sunsail|\bmold\b"), "a known slip"),
]


def check_invariants(top, guides, bundles):
    errs = []
    E = errs.append
    keys = [g["key"] for g in guides]
    if len(keys) != len(set(keys)):
        E("duplicate guide keys")
    # 26, not the "24" of DESIGN.md 3.1's prose: its own roster (RAID 9, HEROIC 6, DUNGEON 4,
    # UNLOCK 5, FLYING 1, BADGES 1) sums to 26, and 33 research guides minus the FLYING merge (1),
    # the BADGES merge (5) and PHASES (1) is 26.
    if len(guides) != 26:
        E("expected 26 guides, got %d" % len(guides))
    # BUILD is the bundles' date: at least one bundle's notes must mention it (3.1)
    noted = any(BUILD in json.dumps(b["verify"].get("notes", "")) + json.dumps(b["data"].get("notes", "")) for b in bundles)
    if not noted:
        E("BUILD %s is not a date the research bundles' notes mention" % BUILD)
    for c in top["CATEGORIES"]:
        if "_" in c["label"] or "C_" in c["label"]:
            E("CATEGORIES label %r carries an underscore" % c["label"])
    for mid, name in top["INSTANCES"].items():
        if "_" in name or "C_" in name:
            E("INSTANCES[%d] %r carries an underscore" % (mid, name))
    map_ids = set(MAPS.values())
    rules = top["RULES"]
    for g in guides:
        gk = g["key"]
        skeys = [s["key"] for s in g["steps"]]
        if len(skeys) != len(set(skeys)):
            E("%s: duplicate step keys" % gk)
        sset = set(skeys)
        if len(g["name"]) > 24:
            E("%s: name over 24: %r" % (gk, g["name"]))
        if not isinstance(g["minLevel"], int):
            E("%s: no numeric minLevel" % gk)
        if (gk in ACCOUNT_WIDE) != bool(g["accountWide"]):
            E("%s: accountWide mismatch" % gk)
        for p in g["prerequisites"]:
            if p["guide"] not in keys or p["guide"] == gk:
                E("%s: prerequisite %s unknown or self" % (gk, p["guide"]))
        if g["alternatives"]:
            for goal, spec in g["alternatives"].items():
                for grp in spec["groups"]:
                    for sk in grp:
                        if sk not in sset:
                            E("%s: alternatives %s names %s" % (gk, goal, sk))
        heroic_rep = [s for s in g["steps"] if s["kind"] == "REP"] if g["category"] == "HEROIC" else []
        if heroic_rep:
            for p in range(1, 6):
                holders = [s for s in heroic_rep if s["phases"]["from"] <= p and (s["phases"]["to"] is False or p <= s["phases"]["to"])]
                if len(holders) != 1 or holders[0]["standing"] != rules[p]["heroicKeyStanding"]:
                    E("%s: REP pair does not match RULES[%d].heroicKeyStanding" % (gk, p))
        for s in g["steps"]:
            sk = s["key"]
            tag = "%s:%s" % (gk, sk)
            if len(s["title"]) > 60:
                E("%s: title over 60 (%d)" % (tag, len(s["title"])))
            if s["kind"] == "QUEST" and s.get("questId") is None and not s.get("questIds"):
                E("%s: QUEST without questId or questIds" % tag)
            if s["kind"] == "REP":
                if s.get("factionId") is None or not (1 <= s["standing"] <= 8):
                    E("%s: REP without factionId or standing" % tag)
                if not s.get("factionName"):
                    E("%s: REP without factionName" % tag)
            if s["kind"] == "ITEM":
                it = s.get("item") or {}
                if it.get("id") is None and not it.get("anyOf"):
                    E("%s: ITEM without item.id or item.anyOf" % tag)
                if "itemId" in s:
                    E("%s: itemId beside item" % tag)
            for row in s.get("places") or []:
                rows = list(row.values()) if ("role" not in row) else [row]
                for r in rows:
                    ok = ("map" in r and "x" in r and "y" in r) or ("instance" in r) or ("item" in r)
                    if not ok:
                        E("%s: place without map/x/y, instance or item: %r" % (tag, r))
                    if "map" in r and r["map"] not in map_ids:
                        E("%s: place map %s not in MAPS" % (tag, r["map"]))
            ph = s.get("phases")
            if not ph or not (1 <= ph["from"] <= 5) or (ph["to"] is not False and not (ph["from"] <= ph["to"] <= 5)):
                E("%s: bad phases %r" % (tag, ph))
            if s.get("consumedBy") and s["consumedBy"] not in sset:
                E("%s: consumedBy target missing" % tag)
            if s.get("consumedBy") and s["kind"] in ("ITEM", "KILL") and s.get("questId") is not None:
                E("%s: ITEM/KILL with questId carries consumedBy" % tag)
            if s.get("impliedBy"):
                all_ids = set()
                for t in g["steps"]:
                    all_ids |= set(quest_ids_of(t))
                for q in s["impliedBy"]:
                    if q not in all_ids:
                        E("%s: impliedBy %d names no step of the guide" % (tag, q))
            if s["kind"] == "MANUAL" and not s.get("note") and not s.get("auto") and tag not in ALLOW_UNKNOWN:
                E("%s: MANUAL without auto or note" % tag)
            if s.get("questMode") == "CHAIN" and s["questIds"][-1] != s.get("questId"):
                E("%s: CHAIN does not end with its questId" % tag)
            if s.get("questMode") == "ALL" and s.get("questId") not in s["questIds"]:
                E("%s: ALL list lacks its questId" % tag)
            # 4.10: counted = not optional, not note, not daily outside the recurring guide. A hub
            # daily keeps optional = false (its line shows the live word, section 2) and is left
            # out of n/m by that rule, so a daily step outside BADGES must be a QUEST the engine
            # can read live and must never sit in an alternatives group or be an accept step.
            if s.get("daily") and gk != "BADGES":
                if s["kind"] != "QUEST" or (s.get("questId") is None and not s.get("questIds")):
                    E("%s: daily step outside BADGES is not a readable QUEST" % tag)
                if s.get("accept") or s.get("consumedBy"):
                    E("%s: daily step outside BADGES carries accept or consumedBy" % tag)
                for goal, spec in (g["alternatives"] or {}).items():
                    if any(sk in grp for grp in spec["groups"]):
                        E("%s: daily step outside BADGES sits in alternatives %s" % (tag, goal))
            if s.get("accept"):
                later = g["steps"][skeys.index(sk) + 1:]
                if not any(t.get("questId") == s["questId"] for t in later):
                    E("%s: accept step has no later turn-in" % tag)
            strings = []
            walk_strings(s, tag, strings)
            for path, text in strings:
                if path.endswith(".key") or path.endswith(".kind") or path.endswith(".questMode") or path.endswith(".section") \
                        or ".classes" in path or path.endswith(".role") or path.endswith(".consumedBy"):
                    continue
                if "_" in text or "C_" in text:
                    E("%s: underscore or client prefix in %s" % (tag, path))
            # splits are whole
            def check_split(v, where):
                if isinstance(v, dict):
                    ks = set(v.keys())
                    if ks & {"A", "H"} and ks != {"A", "H"}:
                        E("%s: faction split not whole at %s" % (tag, where))
                    if ks & {"ALDOR", "SCRYER", "SCRYERS"}:
                        if ks != {"ALDOR", "SCRYER"}:
                            E("%s: side split not whole or spells SCRYERS at %s" % (tag, where))
                    for k2, x in v.items():
                        check_split(x, where + "." + str(k2))
                elif isinstance(v, list):
                    for x in v:
                        check_split(x, where)
            check_split(s, "step")
        for text in (g["title"], g["name"], g["summary"], g["unlocks"], g["phase"]["note"]):
            if text and ("_" in text or "C_" in text):
                E("%s: underscore or client prefix in guide prose" % gk)
        # the player's prose carries no research marker, database id or doubled stop
        prose_strings = [(gk + ".summary", g["summary"]), (gk + ".unlocks", g["unlocks"]), (gk + ".phase.note", g["phase"]["note"])]
        for s in g["steps"]:
            tag = "%s:%s" % (gk, s["key"])
            prose_strings.append((tag + ".title", s["title"]))
            prose_strings.append((tag + ".detail", s.get("detail")))
            for n, v in (s.get("detailByPhase") or {}).items():
                prose_strings.append((tag + ".detailByPhase[%d]" % n, v))
            qn = s.get("questName")
            for v in (qn.values() if isinstance(qn, dict) else [qn]):
                if v and "(" in v and v not in REAL_BRACKET_TITLES:
                    E("%s: questName carries an aside in brackets: %r" % (tag, v))
            if s.get("needsStanding") and s["kind"] != "ITEM":
                E("%s: needsStanding on a %s step (3.8.3: ITEM only)" % (tag, s["kind"]))
            for row in s.get("places") or []:
                for r in (list(row.values()) if "role" not in row else [row]):
                    if (r.get("name") or "").startswith("Started by"):
                        E("%s: a start row named by a sentence: %r" % (tag, r["name"]))
        for where, text in prose_strings:
            if not text:
                continue
            for pat, what in PROSE_BANNED:
                m = pat.search(text)
                if m:
                    E("%s: %s (%r) in %s" % (gk, what, m.group(0), where))
    for n in range(1, 6):
        for sent in rules[n]["sentences"] + [top["PHASES"][n - 1]["notes"]]:
            if "_" in sent or "C_" in sent:
                E("RULES[%d]: underscore in sentence" % n)
    by = {g["key"]: g for g in guides}
    kara = by.get("KARAZHAN_ATTUNEMENT")
    if kara:
        ad = [s for s in kara["steps"] if s["key"] == "arcane_disturbances"][0]
        if 9825 in (ad.get("impliedBy") or []) or 9826 not in (ad.get("impliedBy") or []):
            E("arcane_disturbances.impliedBy must exclude 9825 and include 9826")
    expect = {"KARAZHAN_ATTUNEMENT": 16, "BLACK_TEMPLE_ATTUNEMENT": 17, "NETHERWING_DAILIES": 34, "FLYING": 9, "BADGES": 28}
    for k, n in expect.items():
        if k in by and len(by[k]["steps"]) != n:
            E("%s: expected %d steps, got %d" % (k, n, len(by[k]["steps"])))
    for k in CONSUMED:
        if k == "TK_ATTUNEMENT":
            E("CONSUMED must not name TK_ATTUNEMENT")
    # every PREREQS row reached an emitted guide and names another emitted guide
    for k, rows in PREREQS.items():
        if k not in by:
            E("PREREQS names %s, which is not an emitted guide" % k)
            continue
        have = {p["guide"]: p["hard"] for p in by[k]["prerequisites"]}
        for p in rows:
            t = MERGED.get(p["guide"], p["guide"])
            if t not in by or t == k:
                E("PREREQS %s -> %s unknown or self" % (k, t))
            elif have.get(t) != bool(p["hard"]):
                E("PREREQS %s -> %s did not land with hard = %r" % (k, t, p["hard"]))
    return errs


# ===========================================================================
# Emission (3.8 step 7)
# ===========================================================================

def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", " ") + '"'


LUA_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def lua_key(k):
    if isinstance(k, int):
        return "[%d]" % k
    return k if LUA_IDENT.match(k) else "[%s]" % lua_str(k)


def lua(v, indent=0, keep_nil=False):
    """Deterministic Lua for a Python value: dicts keep insertion order, None is omitted
    (or written as nil for the guide record's fixed fields), False is written."""
    if v is None:
        return "nil"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return ("%g" % v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        parts = [lua(x, indent + 2) for x in v]
        body = ", ".join(parts)
        if len(body) + indent < 110 or all(not isinstance(x, (dict, list)) for x in v):
            return "{ " + body + " }" if parts else "{}"
        pad = " " * (indent + 2)
        return "{\n" + "".join(pad + p + ",\n" for p in parts) + " " * indent + "}"
    if isinstance(v, dict):
        items = [(k, x) for k, x in v.items() if x is not None or keep_nil]
        parts = ["%s = %s" % (lua_key(k), lua(x, indent + 2)) for k, x in items]
        body = ", ".join(parts)
        if not parts:
            return "{}"
        if len(body) + indent < 110 and "\n" not in body:
            return "{ " + body + " }"
        pad = " " * (indent + 2)
        return "{\n" + "".join(pad + p + ",\n" for p in parts) + " " * indent + "}"
    die("cannot emit %r" % (v,))


STEP_ORDER = ["key", "kind", "title", "optional", "note", "daily", "accept", "weekly", "section", "level", "levelByClass",
              "classes", "faction", "side", "phases", "questId", "questIds", "questMode", "altQuestIds", "questName", "choice",
              "item", "questItem", "questItems", "needs", "needsStanding", "provided", "pouch", "cost", "factionId",
              "factionName", "standing", "inside", "auto", "spellId", "anySpell", "skill", "list", "related", "impliedBy",
              "consumedBy", "places", "detail", "detailByPhase"]
GUIDE_ORDER = ["key", "name", "title", "category", "order", "faction", "gate", "phase", "unlock", "accountWide", "minLevel",
               "instance", "recurring", "prerequisites", "alternatives", "summary", "unlocks"]


def emit_step(s):
    unknown = [k for k in s if k not in STEP_ORDER]
    if unknown:
        die("step %s carries fields outside the record: %r" % (s["key"], unknown))
    lines = []
    head = []
    for k in STEP_ORDER:
        if k not in s or s[k] is None:
            continue
        if k in ("places", "detail", "detailByPhase", "list", "choice", "questItems", "inside", "item", "alternatives"):
            continue
        head.append("%s = %s" % (k, lua(s[k], 6)))
    lines.append("    { " + ", ".join(head) + ",")
    for k in ("item", "inside", "list", "choice", "questItems"):
        if s.get(k) is not None:
            lines.append("      %s = %s," % (k, lua(s[k], 6)))
    if s.get("places"):
        lines.append("      places = {")
        for p in s["places"]:
            lines.append("        %s," % lua(p, 8))
        lines.append("      },")
    if s.get("detailByPhase"):
        lines.append("      detailByPhase = {")
        for n in sorted(s["detailByPhase"]):
            lines.append("        [%d] = %s," % (n, lua_str(s["detailByPhase"][n])))
        lines.append("      },")
    if s.get("detail") is not None:
        lines.append("      detail = %s }," % lua_str(s["detail"]))
    else:
        lines[-1] = lines[-1].rstrip(",") + " },"
    return "\n".join(lines)


def emit(top, guides):
    L = []
    w = L.append
    w("-- Commander Quest Log: attunement guides data. GENERATED by Harness/make_attunements.py from the seven")
    w("-- research bundles in Harness/attune_research (research-0..6.json, %s) with every verify.corrections" % BUILD)
    w("-- row applied, then the generator's hand tables (names, merges, phase windows, alternatives, unlock proofs,")
    w("-- implication and consumption). Pure data, no code: the engine that reads it is CommanderQuestLogAttune.lua")
    w("-- and the tab is CommanderQuestLogAttunements.lua. Do not edit by hand: edit the generator and re-run it")
    w("-- (python3 Harness/make_attunements.py; --check exits 1 when this file is stale).")
    w("")
    w("CommanderQuestLogAttuneData = {")
    w("  BUILD = %s," % lua_str(top["BUILD"]))
    w("  SOURCE = %s," % lua_str(top["SOURCE"]))
    w("  -- the five epoch starts; since is compared against GetServerTime(), false = unannounced")
    w("  PHASES = {")
    for p in top["PHASES"]:
        head = {k: p[k] for k in ("n", "short", "name", "blizzard", "since")}
        if "raidsOpen" in p:
            head["raidsOpen"] = p["raidsOpen"]
        w("    { %s," % ", ".join("%s = %s" % (k, lua(v)) for k, v in head.items()))
        w("      notes = %s }," % lua_str(p["notes"]))
    w("  },")
    w("  -- one FULL row per phase, nothing inherited (3.3)")
    w("  RULES = {")
    for n in range(1, 6):
        r = top["RULES"][n]
        w("    [%d] = {" % n)
        for k in ("heroicKeyStanding", "communalPouches", "heroicTuning", "vendorStock", "attunementRequired", "raidsOpen",
                  "badgeSources", "live", "assumed"):
            w("      %s = %s," % (k, lua(r[k], 6)))
        w("      sentences = {")
        for sent in r["sentences"]:
            w("        %s," % lua_str(sent))
        w("      },")
        w("    },")
    w("  },")
    w("  -- in-game proof of a phase: a saved lockout on these maps, these quests flagged or on quest")
    w("  EVIDENCE = { lockouts = %s," % lua(top["EVIDENCE"]["lockouts"]))
    w("               quests = %s }," % lua(top["EVIDENCE"]["quests"]))
    w("  CATEGORIES = {")
    for c in top["CATEGORIES"]:
        w("    { key = %s, label = %s }," % (lua_str(c["key"]), lua_str(c["label"])))
    w("  },")
    w("  -- display names of the instances a step or door names")
    w("  INSTANCES = {")
    for mid in sorted(top["INSTANCES"]):
        w("    [%d] = %s," % (mid, lua_str(top["INSTANCES"][mid])))
    w("  },")
    w("  -- zone name -> uiMapId (the generator's zone lookup, kept for the tab's zone names)")
    w("  MAPS = {")
    for z in top["MAPS"]:
        w("    [%s] = %d," % (lua_str(z), top["MAPS"][z]))
    w("  },")
    w("  -- every instance id a KILL step names or holds one of its bosses, and Outland 530: the engine arms the combat log inside these")
    w("  KILL_MAPS = { %s }," % ", ".join("[%d] = true" % m for m in top["KILL_MAPS"]))
    w("  guides = {},")
    w("}")
    w("local D = CommanderQuestLogAttuneData")
    for g in guides:
        w("")
        w("do")
        w("D.guides[#D.guides + 1] = {")
        w("  key = %s, name = %s, title = %s," % (lua_str(g["key"]), lua_str(g["name"]), lua_str(g["title"])))
        w("  category = %s, order = %d, faction = %s, gate = %s," % (lua_str(g["category"]), g["order"], lua_str(g["faction"]), lua(g["gate"])))
        ph = g["phase"]
        w("  phase = { introduced = %d, requiredUntil = %s," % (ph["introduced"], lua(ph["requiredUntil"])))
        w("            note = %s }," % lua_str(ph["note"]))
        w("  unlock = %s," % lua(g["unlock"], 2))
        w("  accountWide = %s, minLevel = %d, instance = %s, recurring = %s," % (lua(g["accountWide"]), g["minLevel"], lua(g["instance"]), lua(g["recurring"])))
        w("  prerequisites = %s," % lua(g["prerequisites"], 2))
        w("  alternatives = %s," % lua(g["alternatives"], 2))
        w("  summary = %s," % lua_str(g["summary"]))
        w("  unlocks = %s," % lua_str(g["unlocks"]))
        w("  steps = {")
        for s in g["steps"]:
            w(emit_step(s))
        w("  },")
        w("}")
        w("end")
    text = "\n".join(L) + "\n"
    if "\t" in text:
        die("a tab reached the output")
    return text


# ===========================================================================
# Wowhead verification of the three memory ids (A80)
# ===========================================================================

def verify_ids():
    out = []
    for iid, want in VERIFY_IDS.items():
        try:
            req = urllib.request.Request(WOWHEAD % iid, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=15) as r:
                body = json.loads(r.read().decode("utf8"))
            got = body.get("name")
            out.append((iid, want, got, "ok" if got == want else "MISMATCH"))
        except Exception as e:  # noqa: BLE001
            out.append((iid, want, None, "unreachable: %s" % e))
    return out


# ===========================================================================
# Main
# ===========================================================================

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--research", default=DEFAULT_RESEARCH, help="folder holding research-0..6.json")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--check", action="store_true", help="write nothing; exit 1 if the file is stale or an invariant fails")
    ap.add_argument("--verify-ids", action="store_true", help="ask Wowhead's Anniversary tooltip endpoint about the three mount ids")
    args = ap.parse_args()

    ctx = Ctx(load(args.research))
    apply_corrections(ctx)
    guides = build_guides(ctx)
    unused = [i for i in range(len(PROSE_FIXES)) if i not in PROSE_FIXES_USED]
    if unused:
        die("PROSE_FIXES rows never applied: %r" % unused)
    top = build_top(guides)
    errs = check_invariants(top, guides, ctx.bundles)
    text = emit(top, guides)

    report = []
    say = report.append
    say("guides: %d (%s)" % (len(guides), ", ".join("%s %d" % (c, sum(1 for g in guides if g["category"] == c)) for c, _ in CATEGORIES)))
    kinds = {}
    for g in guides:
        for s in g["steps"]:
            kinds[s["kind"]] = kinds.get(s["kind"], 0) + 1
    say("steps: %d (%s)" % (sum(kinds.values()), ", ".join("%s %d" % kv for kv in sorted(kinds.items()))))
    for g in guides:
        counted = sum(1 for s in g["steps"] if not s["optional"] and not s.get("note") and not (s.get("daily") and g["key"] != "BADGES"))
        say("  %-26s %-24s %2d steps, %2d counted, minLevel %s, phase %d..%s" % (
            g["key"], g["name"], len(g["steps"]), counted, g["minLevel"], g["phase"]["introduced"], g["phase"]["requiredUntil"] or "open"))
    say("corrections applied: %d of %d rows" % (len(ctx.applied), sum(len(b["verify"]["corrections"]) for b in ctx.bundles)))
    for bi, ri, key, how in ctx.applied:
        say("  research-%d #%-2d %s / %s [%s]: %s" % (bi, ri, key[0], key[1], key[2], how))
    say("dropped research fields: %s" % ", ".join("%s x%d" % kv for kv in sorted(ctx.dropped.items())))
    for line in ctx.report:
        say(line)
    say("PHASES guide: dropped as a guide; its five corrected details (%d chars) stand behind the PHASE_SENTENCES notes" % sum(len(v) for v in ctx.phases_detail.values()))
    if args.verify_ids:
        for iid, want, got, status in verify_ids():
            say("mount id %d: want %r, endpoint %r: %s" % (iid, want, got, status))
    else:
        say("mount ids 33999, 32458, 34061 (A80): shipped; not asked of the endpoint this run (pass --verify-ids)")
    size = len(text.encode("utf8"))
    say("output: %s, %d bytes%s" % (os.path.relpath(args.out, ADDONS), size, "  WARNING over 400 KB: split a second file (1.1)" if size > WARN_BYTES else ""))
    for e in errs:
        say("INVARIANT FAILED: %s" % e)

    if args.check:
        old = open(args.out, encoding="utf8").read() if os.path.exists(args.out) else None
        stale = old != text
        say("check: %s" % ("STALE: the file on disk differs; re-run without --check" if stale else "the data file is current"))
        print("\n".join(report))
        sys.exit(1 if (stale or errs) else 0)
    if errs:
        print("\n".join(report))
        die("%d invariants failed; nothing written" % len(errs))
    with open(args.out, "w", encoding="utf8", newline="\n") as f:
        f.write(text)
    print("\n".join(report))


if __name__ == "__main__":
    main()
