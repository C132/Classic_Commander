#!/usr/bin/env python3
"""Can the settings page reach every setting the lanes obey?

    python3 Commander_Tracer/Harness/settings_reach.py

The brief for this module was "a lot of options", and the failure mode that
brief always has is not a missing feature -- it is a setting the runtime
really reads, really acts on, and no control on the page can change. Those
are invisible: a lane behaves in a way the user cannot explain and cannot
fix, and nothing in the code looks wrong.

This module stores most of its settings by PATTERN -- <lane><Key> for the
six lanes, <kind>Lane / <kind>Ledger for the twenty-two kinds, one key per
sound slot -- so the walk expands the patterns rather than reading only
literal keys:

  declared   DefaultSettings' literal keys, plus DATA.LANE_DEFAULTS x every
             lane prefix, plus the four HUD chrome keys x every lane, plus
             {Lane, Ledger} x every kind, plus every sound slot
  obeyed     G("Key") and CommanderTracerDB.Key in the runtime; L(P, "Key")
             and cfg.Key in the runtime and engine (a lane key, expanded
             over every prefix); db[rec.kind .. "Lane"/"Ledger"] in the
             engine (expanded over every kind); slot.key / kind.sound
             reads (every sound slot); the CVarBackup table
  reachable  CommanderTracerDB.Key, CommanderTracerDB[P .. "Key"] (expanded),
             CommanderTracerDB[kind.key .. "Lane"] (expanded),
             CommanderTracerDB[slot.key] (every slot), and the chrome keys
             AddHudChromeOptions gives every lane

and reports the two differences that are bugs:

  UNREACHABLE  the runtime obeys it, the page cannot change it
  DEAD         the page can change it, nothing declares it
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

DATA_FILE = os.path.join(ROOT, "CommanderTracerData.lua")
ENGINE_FILE = os.path.join(ROOT, "CommanderTracerEngine.lua")
DB_FILE = os.path.join(ROOT, "CommanderTracerDB.lua")
RUNTIME_FILE = os.path.join(ROOT, "CommanderTracer.lua")

CHROME_KEYS = ("Style", "Scale", "Locked", "Pos")

# Deliberately off the page
INTERNAL = {"CVarBackup", "Migrated"}


def read(path):
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def table_keys(src, header):
    """Top-level keys of `local NAME = {` / `DATA.NAME = {` starting at header."""
    start = src.index(header)
    depth, i = 0, start + len(header) - 1
    keys = set()
    for match in re.finditer(r"[{}]|^\s*(\w+)\s*=", src[i:], re.M):
        if match.group(0) in "{}":
            depth += 1 if match.group(0) == "{" else -1
            if depth == 0:
                break
        elif depth == 1 and match.group(1):
            keys.add(match.group(1))
    return keys


def list_field(src, header, field):
    """Every `field = "X"` inside the list that starts at header."""
    start = src.index(header)
    depth, i = 0, start + len(header) - 1
    end = None
    for match in re.finditer(r"[{}]", src[i:]):
        depth += 1 if match.group(0) == "{" else -1
        if depth == 0:
            end = i + match.end()
            break
    body = src[i:end]
    return re.findall(r'\b%s\s*=\s*"(\w+)"' % field, body)


def main():
    data = read(DATA_FILE)
    engine = read(ENGINE_FILE)
    db = read(DB_FILE)
    runtime = read(RUNTIME_FILE)

    lanes = list_field(data, "DATA.LANES = {", "key")
    kinds = list_field(data, "DATA.KINDS = {", "key")
    slots = list_field(data, "DATA.SOUND_SLOTS = {", "key")
    lane_keys = table_keys(data, "DATA.LANE_DEFAULTS = {")

    # declared
    declared = table_keys(db, "local DefaultSettings = {")
    for lane in lanes:
        for key in lane_keys:
            declared.add(lane + key)
        for key in CHROME_KEYS:
            declared.add(lane + key)
    for kind in kinds:
        declared.add(kind + "Lane")
        declared.add(kind + "Ledger")
    declared |= set(slots)

    # obeyed
    obeyed = set()
    for src in (runtime, engine):
        obeyed |= set(re.findall(r'\bG\(\s*"(\w+)"', src))
        obeyed |= set(re.findall(r"CommanderTracerDB\.(\w+)", src))
        for key in set(re.findall(r'\bL\(\s*\w+\s*,\s*"(\w+)"', src)) | set(re.findall(r"\bcfg\.(\w+)", src)):
            if key in lane_keys:
                for lane in lanes:
                    obeyed.add(lane + key)
    for suffix in re.findall(r'rec\.kind\s*\.\.\s*"(\w+)"', engine):
        for kind in kinds:
            obeyed.add(kind + suffix)
    if "slot.key" in runtime or "kind.sound" in runtime or 'PlaySlot("SoundCrit")' in runtime:
        obeyed |= set(slots)
    if "ApplyHudChrome(" in runtime:
        for lane in lanes:
            for key in CHROME_KEYS:
                obeyed.add(lane + key)
    obeyed |= INTERNAL & set(re.findall(r"db\.(\w+)", runtime + db))

    # reachable
    reachable = set(re.findall(r"CommanderTracerDB\.(\w+)", db))
    for key in re.findall(r'CommanderTracerDB\[\s*P\s*\.\.\s*"(\w+)"\s*\]', db):
        for lane in lanes:
            reachable.add(lane + key)
    for suffix in re.findall(r'CommanderTracerDB\[\s*kind\.key\s*\.\.\s*"(\w+)"\s*\]', db):
        for kind in kinds:
            reachable.add(kind + suffix)
    if re.search(r"CommanderTracerDB\[\s*slot\.key\s*\]", db):
        reachable |= set(slots)
    if re.search(r"AddHudChromeOptions\(panel,\s*CommanderTracerDB,\s*P\b", db):
        for lane in lanes:
            for key in CHROME_KEYS:
                reachable.add(lane + key)
    if re.search(r'CommanderTracerDB\[\s*lane\.key\s*\.\.\s*"Locked"\s*\]', db):
        for lane in lanes:
            reachable.add(lane + "Locked")

    unreachable = sorted((obeyed | declared) - reachable - INTERNAL)
    dead = sorted(reachable - declared - INTERNAL)
    unread = sorted(declared - obeyed - INTERNAL)

    print("%d lanes, %d kinds, %d sound slots; %d settings declared, %d read by the runtime, "
          "%d reachable from the page"
          % (len(lanes), len(kinds), len(slots), len(declared), len(obeyed), len(reachable)))

    problems = 0
    if unreachable:
        problems += len(unreachable)
        print("\nUNREACHABLE -- the lanes obey these, the page cannot change them:")
        for key in unreachable:
            print("   ", key)
    if dead:
        problems += len(dead)
        print("\nDEAD -- the page writes these, nothing declares them:")
        for key in dead:
            print("   ", key)
    if unread:
        problems += len(unread)
        print("\nUNREAD -- declared and on the page, but nothing obeys them:")
        for key in unread:
            print("   ", key)

    if not problems:
        print("\nevery setting is reachable, every control writes a real setting, "
              "and every setting is obeyed.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
