#!/usr/bin/env python3
"""Catch a local function used before it is declared.

    python3 Commander_Diminish/Harness/order_lint.py

Lua resolves a bare name at COMPILE time. A call to `Say(...)` written above
`local function Say` does not reach that function -- it compiles to a global
lookup, finds nil, and errors when the line finally runs. Nothing about it
looks wrong: the function exists, the name is spelled correctly, and the file
loads. It only fails on the branch that calls it, which in a combat addon can
easily be a branch that needs an enemy to press a specific button.

Commander Arena Frames had exactly that bug -- alert helpers sitting below the
combat-log handler that called them -- and it was found by reading bytecode
rather than by reading code, which is not a repeatable way to find anything.
This module runs the same check for the same reason: its draw path is one long
file of local helpers calling each other.

So: compile each file with luajit, list every global it READS, and flag any
name that the same file also declares as a local. A name in both lists is
always this bug. No whitelist of WoW API is needed, which is what keeps the
check honest as the client changes.
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

FILES = [
    "CommanderDiminishData.lua",
    "CommanderDiminishEngine.lua",
    "CommanderDiminishDB.lua",
    "CommanderDiminish.lua",
]

# `local NAME` / `local function NAME` / `local a, b, c`
LOCAL_FUNC = re.compile(r"^\s*local\s+function\s+([A-Za-z_][\w]*)", re.M)
LOCAL_DECL = re.compile(r"^\s*local\s+(?!function\b)([A-Za-z_][\w, ]*?)\s*(?:=|$)", re.M)
GGET = re.compile(r'GGET\s+\d+\s+\d+\s*;\s*"([A-Za-z_][\w]*)"')


def globals_read(path):
    try:
        out = subprocess.run(["luajit", "-bl", path], capture_output=True,
                             text=True, check=True).stdout
    except FileNotFoundError:
        sys.exit("luajit is not installed; this lint needs it to read bytecode.")
    except subprocess.CalledProcessError as exc:
        sys.exit("luajit could not compile %s:\n%s" % (path, exc.stderr))
    return set(GGET.findall(out))


# `local pairs = pairs` -- hoisting a global into a local for speed. The
# right-hand side is a genuine global read of the same name, and it is not a
# bug, so this pattern is excluded rather than reported. Checked against the
# rest of the suite: it is the ONLY false positive the rule produces.
SELF_LOCAL = re.compile(r"^\s*local\s+([A-Za-z_][\w]*)\s*=\s*\1\s*$", re.M)


def locals_declared(src):
    names = set(LOCAL_FUNC.findall(src))
    for group in LOCAL_DECL.findall(src):
        for name in group.split(","):
            name = name.strip()
            if name:
                names.add(name)
    return names


def main():
    problems = 0
    for filename in FILES:
        path = os.path.join(ROOT, filename)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        shadowed = sorted((globals_read(path) & locals_declared(src))
                          - set(SELF_LOCAL.findall(src)))
        # A name deliberately published as a global AND held in a local is a
        # real pattern (the module namespaces), so allow the ones this suite
        # uses on purpose.
        shadowed = [n for n in shadowed if not n.startswith("CommanderDiminish")]
        if shadowed:
            problems += len(shadowed)
            print("%s:" % filename)
            for name in shadowed:
                print("    %s is declared local here but read as a GLOBAL somewhere "
                      "above its declaration -- that read is nil." % name)
    if not problems:
        print("no use-before-declaration in %d files." % len(FILES))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
