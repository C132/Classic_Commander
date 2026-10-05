#!/usr/bin/env python3
"""Generate the shaded bands for the Commander_PartyFrames dials.

A dial's absorb band is a donut the client masks radially (it is the swipe
texture of a Cooldown frame) and tints with the shield's colour. A plain white
donut therefore comes out as a flat block of that colour -- which is the Flat
bar style, and the only one the dials had.

These are the same donut with the board's OTHER bar styles wrapped round it.
A bar carries its shape down its height and nothing across its width (see
make_bars.py); a band carries it across its THICKNESS and nothing round its
length, for the same reason -- the arc is cut to a fraction, and detail along
it would be cut with it. So each profile here is make_bars.py's own, read from
the band's outer edge (the top of the bar, where the light is) to its inner
one.

Blizzard is the exception: the bars use the game's own status-bar file, which
cannot be read from here, so its profile is drawn to match -- a lit lip just
under the top edge falling away to a darker foot.

White art with the shading in the RGB: the tint multiplies, so luminance here
is shading on whatever colour the shield wears.

    python3 make_dials.py ../Textures
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_bars import bevel, glass, gloss, ridge, smoothstep, write_png  # noqa: E402

SIZE = 128
SS = 4                      # supersamples per axis
OUTER = 0.485               # the donut's outer radius over the texture's width
RATIO = 0.71                # inner radius over outer: the dial's band weight


def blizzard():
    """The stock status bar: a bright lip under the top edge, a darker foot."""
    def profile(v):
        lip = 0.74 + 0.26 * smoothstep(v / 0.2)
        fall = 1.0 - 0.44 * smoothstep((v - 0.28) / 0.72) if v > 0.28 else 1.0
        return lip * fall, 1.0

    return profile


def flat():
    return lambda v: (1.0, 1.0)


def render(profile):
    """A donut whose luminance follows profile(v), v = 0 at the outer edge."""
    centre = SIZE / 2.0
    outer = OUTER * SIZE
    inner = outer * RATIO
    pixels = bytearray(SIZE * SIZE * 4)
    step = 1.0 / SS
    offset = step / 2.0
    for py in range(SIZE):
        for px in range(SIZE):
            light, cover = 0.0, 0.0
            for sy in range(SS):
                y = py + offset + sy * step - centre
                for sx in range(SS):
                    x = px + offset + sx * step - centre
                    radius = math.hypot(x, y)
                    if inner <= radius <= outer:
                        value, _ = profile((outer - radius) / (outer - inner))
                        light += max(0.0, min(1.0, value))
                        cover += 1.0
            index = (py * SIZE + px) * 4
            # Averaged over the covered samples only, so the antialiased rim
            # fades in alpha without also fading toward black
            level = int((light / cover if cover else 1.0) * 255 + 0.5)
            pixels[index] = level
            pixels[index + 1] = level
            pixels[index + 2] = level
            pixels[index + 3] = int(cover / (SS * SS) * 255 + 0.5)
    return pixels


BANDS = {
    "DialRing": flat,
    "DialRingBlizzard": blizzard,
    "DialRingGloss": gloss,
    "DialRingBevel": bevel,
    "DialRingRidge": ridge,
    "DialRingGlass": glass,
}


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "../Textures"
    os.makedirs(target, exist_ok=True)
    for name, builder in sorted(BANDS.items()):
        path = os.path.join(target, name + ".png")
        write_png(path, render(builder()), SIZE, SIZE)
        print(path)


if __name__ == "__main__":
    main()
