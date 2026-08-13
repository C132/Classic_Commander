#!/usr/bin/env python3
"""Generate the Commander_PartyFrames bar art.

Every bar on a row is a plain Texture whose WIDTH is set to the fill fraction --
a 40% health bar is the same art squashed into 40% of the room. Horizontal
detail would therefore compress differently at every fill level, so all of this
art is uniform across its width and carries its shape in the vertical only.
That is the one rule here; everything else is taste.

White art with the shading in the RGB, alpha left solid: the board tints every
bar with SetVertexColor, which multiplies, so luminance here comes out as
shading on whatever color a row happens to be wearing.

    python3 make_bars.py ../Textures
"""

import math
import os
import struct
import sys
import zlib

WIDTH = 16                  # uniform across its width; this is just enough to filter cleanly
HEIGHT = 64
SS = 8                      # supersamples per axis


def write_png(path, pixels, width, height):
    raw = bytearray()
    for y in range(height):
        raw.append(0)                       # filter type 0 (None)
        raw.extend(pixels[y * width * 4:(y + 1) * width * 4])

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    blob = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(blob)


def render(profile, width=WIDTH, height=HEIGHT):
    """profile(v) -> (luminance, alpha) for v in 0..1 down the bar's height."""
    pixels = bytearray(width * height * 4)
    step = 1.0 / SS
    offset = step / 2.0
    for py in range(height):
        light, opacity = 0.0, 0.0
        for sy in range(SS):
            value, alpha = profile((py + offset + sy * step) / height)
            light += value
            opacity += alpha
        light, opacity = light / SS, opacity / SS
        level = int(max(0.0, min(1.0, light)) * 255 + 0.5)
        alpha = int(max(0.0, min(1.0, opacity)) * 255 + 0.5)
        for px in range(width):
            index = (py * width + px) * 4
            pixels[index] = level
            pixels[index + 1] = level
            pixels[index + 2] = level
            pixels[index + 3] = alpha
    return pixels


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def gloss():
    """Lit from above and falling away: the shape a bar has when it is a tube.

    The quietest of these -- no hard line anywhere, so it survives being squeezed
    into the half-height personal rows without turning into a stripe pattern.
    """
    def profile(v):
        base = 1.0 - 0.38 * smoothstep(v)
        sheen = 0.10 * math.exp(-((v - 0.16) / 0.13) ** 2)
        return base + sheen, 1.0

    return profile


def bevel():
    """Flat through the middle with a lit top edge and a shaded bottom one.

    Reads as a solid block at a glance -- the board's own look -- with just
    enough edge to separate a row's bar from the row under it.
    """
    def profile(v):
        if v < 0.14:
            return 1.0 - 0.10 * smoothstep(v / 0.14), 1.0
        if v > 0.84:
            return 0.90 - 0.36 * smoothstep((v - 0.84) / 0.16), 1.0
        return 0.90, 1.0

    return profile


def ridge():
    """Brushed metal: fine striations across the height under a soft gloss.

    The stripes are cheap detail that only shows on a tall bar; on a 6px row it
    averages back down to the gloss it is built on, which is the point.
    """
    def profile(v):
        base = 0.96 - 0.30 * smoothstep(v)
        # Kept coarse on purpose: a finer grain beats against the row height and
        # crawls when the board is scaled
        grain = 0.055 * math.sin(v * math.pi * 9.0)
        return base + grain, 1.0

    return profile


def glass():
    """A hard cut across the middle: bright plate over a dim one.

    The loudest of the four and the most three-dimensional. Strong tints carry
    it best; on a pale bar the lower half can read as a different color.
    """
    def profile(v):
        if v < 0.5:
            return 1.0 - 0.12 * (v / 0.5), 1.0
        return 0.66 - 0.14 * smoothstep((v - 0.5) / 0.5), 1.0

    return profile


def socket():
    """The empty track a bar runs in: dark, with the light caught at the bottom.

    Inverted on purpose -- shadow gathers under the lip a fill would sit behind,
    so an empty bar reads as a groove rather than a painted rectangle.
    """
    def profile(v):
        base = 0.30 + 0.34 * smoothstep(v)
        shade = 0.26 * (1.0 - smoothstep(v / 0.35)) if v < 0.35 else 0.0
        return base - shade, 1.0

    return profile


PROFILES = {
    "BarGloss": gloss,
    "BarBevel": bevel,
    "BarRidge": ridge,
    "BarGlass": glass,
    "BarSocket": socket,
}


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "../Textures"
    os.makedirs(target, exist_ok=True)
    for name, builder in sorted(PROFILES.items()):
        path = os.path.join(target, name + ".png")
        write_png(path, render(builder()), WIDTH, HEIGHT)
        print(path)


if __name__ == "__main__":
    main()
