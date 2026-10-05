#!/usr/bin/env python3
"""Copy the radial disc's art from Commander Plates.

This module does not own a generator. The rings come from Commander Casting's
make_rings.py, the glows and the clock-wipe halves from Commander Plates'
make_glows.py and make_wipe.py; Plates carries all of them, and this copies
the ones the cooldown disc draws with into Textures/ so Production keeps
working with Plates disabled. The smoke diffs every copy against Plates',
byte for byte, so art regenerated over there and not copied here is a red
test rather than two addons quietly drawing different rings.

    python3 Harness/copy_radial_art.py
"""
import os
import shutil

FILES = (
    ["Ring%d.png" % i for i in range(1, 7)]
    + ["CircleMask.png", "Edge.png", "HalfLeft.png", "HalfRight.png"]
    + ["Glow%s.png" % name for name in (
        "Soft", "Ember", "Runic", "Arcane", "Radiant",
        "Frost", "Void", "Halo", "Sigil", "Storm")]
)


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    source = os.path.join(os.path.dirname(here), "Commander_Plates", "Textures")
    target = os.path.join(here, "Textures")
    os.makedirs(target, exist_ok=True)
    for name in FILES:
        shutil.copyfile(os.path.join(source, name), os.path.join(target, name))
    print("copied %d files into %s" % (len(FILES), target))


if __name__ == "__main__":
    main()
