#!/usr/bin/env python3
"""Regenerate the crowd-control block in CommanderPlatesData.lua.

    python3 Commander_Plates/Harness/make_cc_table.py

The big "loose control" icon on a plate has to know which debuffs ARE control,
and the honest answer to that already exists in this suite: Commander
Diminish's DR_BY_SPELL, 884 spell ids across sixteen categories, produced by
Commander Arena Frames' make_dr_table.py from the server's own classifier over
the client's own spell tables. This script does not classify anything. It
reads that table and writes it here, category by category, between the
BEGIN/END GENERATED markers in the data file.

Three addons, three copies, ONE generator -- the same arrangement Diminish has
with Arena Frames, for the same reason: this module has to draw a stunned
target with Diminish disabled, and the diff in Harness/plates_engine_smoke.lua
(section A) turns the copies drifting apart into a red test instead of a
Polymorph the big icon quietly stops recognising.

After a client patch: rerun make_dr_table.py into Arena Frames, paste into
Diminish, then run this.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ADDONS = os.path.dirname(ROOT)

SOURCE = os.path.join(ADDONS, "Commander_Diminish", "CommanderDiminishData.lua")
TARGET = os.path.join(ROOT, "CommanderPlatesData.lua")

BEGIN = "-- BEGIN GENERATED (Harness/make_cc_table.py)"
END = "-- END GENERATED"


def read_by_spell(path):
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    start = src.index("DATA.DR_BY_SPELL = {")
    body = src[start:src.index("\n}", start)]
    pairs = re.findall(r"\[(\d+)\]\s*=\s*\"([A-Z_]+)\"", body)
    table = {}
    for spell, group in pairs:
        table[int(spell)] = group
    header = re.search(r"-- Client build ([\d.]+)", src)
    return table, (header.group(1) if header else "unknown")


def render(table, build):
    by_group = {}
    for spell, group in table.items():
        by_group.setdefault(group, []).append(spell)
    lines = [BEGIN,
             "-- Copied from Commander_Diminish/CommanderDiminishData.lua DR_BY_SPELL",
             "-- (client build %s, %d spells, %d groups). Do not hand-edit."
             % (build, len(table), len(by_group)),
             "DATA.CC_BY_SPELL = {"]
    for group in sorted(by_group):
        ids = sorted(by_group[group])
        lines.append("    -- %s (%d)" % (group, len(ids)))
        row = []
        for spell in ids:
            row.append('[%d] = "%s",' % (spell, group))
            if len(row) == 4:
                lines.append("    " + " ".join(row))
                row = []
        if row:
            lines.append("    " + " ".join(row))
    lines.append("}")
    lines.append(END)
    return "\n".join(lines)


def main():
    if not os.path.exists(SOURCE):
        sys.exit("Commander_Diminish is not installed next to this addon; "
                 "nothing to copy from.")
    table, build = read_by_spell(SOURCE)
    with open(TARGET, encoding="utf-8") as fh:
        src = fh.read()
    a, b = src.index(BEGIN), src.index(END) + len(END)
    out = src[:a] + render(table, build) + src[b:]
    if out != src:
        with open(TARGET, "w", encoding="utf-8") as fh:
            fh.write(out)
        print("wrote %d spells into %s" % (len(table), os.path.relpath(TARGET, ADDONS)))
    else:
        print("already current: %d spells" % len(table))
    return 0


if __name__ == "__main__":
    sys.exit(main())
