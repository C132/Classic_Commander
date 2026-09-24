#!/usr/bin/env python3
"""Can the settings page reach every setting the plates obey?

    python3 Commander_Plates/Harness/settings_reach.py

The brief for this module was "highly configurable", and the failure mode that
claim always has is not a missing feature -- it is a setting the engine really
reads, really acts on, and no control on the page can change. Those are
invisible: the tracker behaves in a way the user cannot explain and cannot fix,
and nothing in the code looks wrong.

So this walks the three files and answers it mechanically:

  1. every key in the DefaultSettings table (the settings that exist)
  2. every key the engine reads via DB("Key", ...) (the settings that matter)
  3. every key the settings page names inside a get/set closure (the settings
     that can be changed)

and reports the two differences that are bugs:

  UNREACHABLE  the engine obeys it, the page cannot change it
  DEAD         the page can change it, nothing reads it

INTERNAL below is the only hand-maintained part: keys that are deliberately
not on the page (saved position, a migration revision, a per-item override
table edited through a grid rather than a named control). Anything not listed
there is expected to be reachable, which is the safe default -- it produces a
complaint to look at rather than silence.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

DB_FILE = os.path.join(ROOT, "CommanderPlatesDB.lua")
ENGINE_FILES = [
    os.path.join(ROOT, "CommanderPlates.lua"),
    os.path.join(ROOT, "CommanderPlatesEngine.lua"),
    os.path.join(ROOT, "CommanderPlatesRadial.lua"),
]
DATA_FILE = os.path.join(ROOT, "CommanderPlatesData.lua")

# Not expected to have a control of their own.
INTERNAL = set()   # nothing is deliberately off the page; see the DATA walks in main()


def read(path):
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def defaults_keys(src):
    """Keys declared in the DefaultSettings table (top-level only)."""
    start = src.index("local DefaultSettings = {")
    depth, i = 0, start + len("local DefaultSettings = ")
    keys, line_depth = set(), None
    for match in re.finditer(r"[{}]|^\s*(\w+)\s*=", src[i:], re.M):
        if match.group(0) in "{}":
            depth += 1 if match.group(0) == "{" else -1
            if depth == 0:
                break
        elif depth == 1 and match.group(1):
            keys.add(match.group(1))
    return keys


def engine_keys(sources):
    """Every setting the engine reads.

    Two spellings count, because both are real: the DB("Key", default)
    accessor that almost everything goes through, and a direct
    CommanderPlatesDB.Key -- which the enable check uses, since it runs
    before the accessor would have a default to fall back on.
    """
    keys = set()
    for src in sources:
        keys |= set(re.findall(r'\bDB\(\s*"(\w+)"', src))
        keys |= set(re.findall(r'\bS\(\s*"(\w+)"', src))
        # the radial brushes read their block through a local G(key, default)
        keys |= set(re.findall(r'\bG\(\s*"(\w+)"', src))
        keys |= set(re.findall(r"CommanderPlatesDB\.(\w+)", src))
    return keys


def page_keys(src):
    """Every CommanderPlatesDB.Key the settings page reads or writes."""
    return set(re.findall(r"CommanderPlatesDB\.(\w+)", src))


def main():
    db_src = read(DB_FILE)
    engine_src = [read(path) for path in ENGINE_FILES]
    if not any(engine_src):
        print("note: the engine file does not exist yet -- checking the page "
              "against DefaultSettings only.\n")

    declared = defaults_keys(db_src)
    obeyed = engine_keys(engine_src)
    reachable = page_keys(db_src)

    # DATA.KIND toggles are read by the engine as S(spec.toggle): resolve them
    # from the data file so they count as obeyed
    data_src = read(DATA_FILE)
    toggles = set(re.findall(r'toggle\s*=\s*"(\w+)"', data_src))
    obeyed |= toggles
    # The CVar profile: declared, reached and applied by iterating DATA.CVARS
    cvar_keys = set(re.findall(r'key\s*=\s*"(Cv\w+)"', data_src))
    declared |= cvar_keys
    reachable |= cvar_keys
    obeyed |= cvar_keys

    unreachable = sorted((obeyed | declared) - reachable - INTERNAL)
    dead = sorted(reachable - declared - INTERNAL)
    unread = sorted(declared - obeyed - INTERNAL) if any(engine_src) else []

    print("%d settings declared, %d read by the engine, %d reachable from the page"
          % (len(declared), len(obeyed), len(reachable)))

    problems = 0
    if unreachable:
        problems += len(unreachable)
        print("\nUNREACHABLE -- the tracker obeys these, the page cannot change them:")
        for key in unreachable:
            print("   ", key)
    if dead:
        problems += len(dead)
        print("\nDEAD -- the page writes these, DefaultSettings does not declare them:")
        for key in dead:
            print("   ", key)
    if unread:
        print("\nnot read by the engine yet (fine while it is still being built):")
        print("   ", ", ".join(unread))

    if not problems:
        print("\nevery setting is reachable, and every control writes a real setting.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
