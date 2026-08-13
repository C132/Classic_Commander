#!/usr/bin/env python3
"""Which settings can each class layer's settings page actually reach?

    python3 settings_reach.py

The engine reads its saved variables through DB("Key", default). The settings
file builds FOUR pages, one per class layer, and for most of its life it built
them as four near-copies of one page — which is exactly the shape that lets a
control quietly go missing from one copy. It did, repeatedly: DispelShowAll
reachable only by priests, DispelHealGlow by everyone but mages, IntRefreshAt
by everyone but priests, all three while the engine read them on every layer.

So this walks the pair of files and answers the question directly:

  1. every DB("Key") the engine reads, plus every key named in a per-layer key
     table (SDATA.*_KEY), which is how a layer points at its own saved variable
  2. every page span in the settings file, with the shared builders it calls
     expanded inline, so a control lives wherever it is really reachable from
  3. the difference, minus the keys that are deliberately layer-scoped

LAYER_SCOPED below is the only hand-maintained part: it is the claim "this
setting belongs to these layers and no others". A key not listed there is
assumed to apply to every page, which is the safe default — it produces a
complaint to investigate rather than silence.

One limit worth knowing: a shared builder can hold a control behind a per-layer
flag (`if ui.shieldSwipe then`), and this reads text rather than running Lua, so
it counts that control as present on every page calling the builder. That is
only ever an OVER-count, so it cannot hide a missing control — the thing this
exists to catch — and LAYER_SCOPED still records where such a setting really
belongs. Do not read a clean run as proof that a layer-scoped control is absent
from the pages it does not belong to.

Exit status is 1 if anything is unreachable, so this can gate a commit.
"""

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
ENGINE = os.path.join(ADDON, "CommanderPartyFrames.lua")
SETTINGS = os.path.join(ADDON, "CommanderPartyFramesDB.lua")

# The settings each layer owns outright. Everything else is chassis and has to
# be reachable from all four pages.
LAYER_SCOPED = {
    # Priest — the absorb board's own vocabulary
    "RenewFlash": {"PWS"},
    "RenewRefreshAt": {"PWS"},
    "ShieldSwipe": {"PWS"},
    "LowAbsorbPct": {"PWS"},
    "LowTimeSecs": {"PWS"},
    "PriestBannerCooldowns": {"PWS"},
    # Mage — self-shield rows and the conjure cluster
    "SelfShieldRows": {"INT"},
    "TrackManaShield": {"INT"},
    "TrackWards": {"INT"},
    "ShowGemButton": {"INT"},
    "ShowPortalButton": {"INT"},
    "MageBannerCooldowns": {"INT"},
    # Druid
    "HotReadyAt": {"HOT"},
    "HotRefreshAt": {"HOT"},
    "HotBannerCooldowns": {"HOT"},
    # Paladin
    "BlessReadyAt": {"BLESS"},
    "BlessRefreshAt": {"BLESS"},
    "BlessBannerCooldowns": {"BLESS"},
    # The mana strip only exists on the layers whose main bar is health
    "ShowManaBar": {"INT", "HOT", "BLESS"},
}

PAGES = [
    ("INT", "    if mageMode then"),
    ("HOT", "    if druidMode then"),
    ("BLESS", "    if palaMode then"),
    ("PWS", "    -- ---- Priest ally board"),
]

# Shared builders whose bodies count as part of every page that calls them.
# DISCOVERED, not listed: every extraction from the four pages adds another
# one, and a hardcoded list that falls behind reports the settings inside the
# new builder as unreachable from all four pages at once — which is what
# happened on the first three extractions, every time, before this was a
# pattern. Anything at file scope taking `panel` as its first argument counts.
BUILDER = re.compile(r"^local function (\w+)\(panel[,)]")

# A page can also reach a setting through a file-scope option table it hands
# straight to the panel — panel:AddDropdown(BAR_TEXTURE_OPTION). Those are as
# reachable as anything written inline, so their bodies are pulled in the same
# way the builders' are.
OPTION_TABLE = re.compile(r"^local ([A-Z][A-Z0-9_]*(?:OPTION|OPTIONS)) = \{")


def read(path):
    return io.open(path, encoding="utf-8").read()


def engine_keys(src):
    keys = set(re.findall(r'DB\("([A-Za-z_]+)"', src))
    # A layer that points at its own saved variable does it through a key
    # table (SDATA.BANNER_CD_KEY, SDATA.STRIP_REFRESH_KEY); the strings in
    # there are read just as surely as a literal DB("...") call.
    for table in re.findall(r"SDATA\.\w+_KEY = \{(.*?)\}", src, re.S):
        keys |= set(re.findall(r'"(\w+)"', table))
    return keys


def builder_bodies(lines):
    """name -> body, for both shared builders and shared option tables.

    A builder ends at a bare `end`; an option table at a bare `}`. Both are at
    file scope, so column zero is the terminator either way.
    """
    bodies = {}
    for i, line in enumerate(lines):
        m = BUILDER.match(line)
        if not m:
            continue
        body = []
        for j in range(i, len(lines)):
            body.append(lines[j])
            if lines[j] == "end":
                break
        bodies[m.group(1)] = body
    for i, line in enumerate(lines):
        m = OPTION_TABLE.match(line)
        if not m:
            continue
        body = []
        for j in range(i, len(lines)):
            body.append(lines[j])
            if lines[j] == "}":
                break
        bodies[m.group(1)] = body
    return bodies


def page_keys(lines):
    bodies = builder_bodies(lines)
    starts = []
    for name, marker in PAGES:
        i = next((i for i, l in enumerate(lines) if l.startswith(marker)), None)
        if i is None:
            sys.exit("could not find the %s page (marker: %r)" % (name, marker))
        starts.append((name, i))
    last = starts[-1][1]
    tail = next(i for i in range(last, len(lines)) if lines[i] == "end")

    out = {}
    for n, (name, a) in enumerate(starts):
        b = starts[n + 1][1] if n + 1 < len(starts) else tail
        # Expansion has to run to a fixed point, not once: a shared builder can
        # itself hand a shared option table to the panel, and a single pass
        # would report the settings in that table as unreachable from every
        # page. (It did, the moment the identity section was extracted.)
        expanded = list(lines[a:b])
        pulled = set()
        while True:
            text = "\n".join(expanded)
            more = [n for n, _ in bodies.items()
                    if n not in pulled
                    and (n + "(panel" in text or "(" + n + ")" in text)]
            if not more:
                break
            for n in more:
                pulled.add(n)
                expanded.extend(bodies[n])
        out[name] = set(re.findall(r"CommanderPartyFramesDB\.([A-Za-z_]+)",
                                   "\n".join(expanded)))
    return out


def main():
    keys = engine_keys(read(ENGINE))
    pages = page_keys(read(SETTINGS).split("\n"))
    every = {name for name, _ in PAGES}

    problems = []
    for key in sorted(keys):
        want = LAYER_SCOPED.get(key, every)
        absent = sorted(want - set(p for p in want if key in pages[p]))
        if absent:
            problems.append((key, absent))

    if not problems:
        print("settings_reach: OK — every setting the engine reads is "
              "reachable from every page it applies to")
        print("  %d keys checked across %d pages" % (len(keys), len(every)))
        return 0

    print("settings_reach: %d setting(s) the engine reads that a page "
          "cannot reach\n" % len(problems))
    for key, absent in problems:
        print("  %-24s unreachable on %s" % (key, ", ".join(absent)))
    print("\nEither add the control to those pages, or — if the setting really "
          "\nis layer-scoped — say so in LAYER_SCOPED at the top of this file.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
