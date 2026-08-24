#!/usr/bin/env python3
"""Generate the Commander suite's shared icon art.

This lives in Commander_Events because every other Commander addon lists it as
a RequiredDep -- one copy of the art, loaded before anything that draws with
it, instead of the same four files duplicated forty times.

Two shapes of the same idea:

  IconDeboss*.png   square, for the square spell icons the suite draws
                    everywhere -- ability strips, dispel slots, consumables
  IconWell*.png     round, for icons standing in for a portrait

Both are shading, not art: transparent through the middle, dark where a recess
would block the light and bright where it would catch. Drawn OVER an icon at
the icon's own size, they make it read as set into the frame rather than pasted
onto it.

    python3 make_icons.py ../Textures
"""

import math
import os
import struct
import sys
import zlib

SIZE = 64
SS = 4                      # supersamples per axis


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


def render(shade, width=SIZE, height=SIZE):
    """shade(u, v) -> (value, alpha) over 0..1, value 0 dark .. 1 light.

    Averaged premultiplied, so a dark edge and a light one never bleed into
    each other as grey where they meet.
    """
    pixels = bytearray(width * height * 4)
    step = 1.0 / SS
    offset = step / 2.0
    samples = SS * SS
    for py in range(height):
        for px in range(width):
            weighted, total = 0.0, 0.0
            for sy in range(SS):
                v = (py + offset + sy * step) / height
                for sx in range(SS):
                    u = (px + offset + sx * step) / width
                    value, alpha = shade(u, v)
                    weighted += value * alpha
                    total += alpha
            alpha = total / samples
            value = (weighted / total) if total > 0 else 0.0
            level = int(max(0.0, min(1.0, value)) * 255 + 0.5)
            index = (py * width + px) * 4
            pixels[index] = level
            pixels[index + 1] = level
            pixels[index + 2] = level
            pixels[index + 3] = int(max(0.0, min(1.0, alpha)) * 255 + 0.5)
    return pixels


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def band(distance, depth):
    """1 hard against an edge, 0 once `depth` away from it."""
    return smoothstep(1.0 - distance / depth) if distance < depth else 0.0


def square(depth, shadow, ambient, highlight, rim=0.0, rim_width=0.05,
           light_depth=0.5):
    """An inner shadow for a square icon.

    Light from above: the top inside wall is in shadow, the bottom one catches
    it, and the sides carry a share of the shadow so the recess closes all the
    way round. The catch light peaks just INSIDE the dark edge rather than on
    it -- stacking the two on the same pixels reads as a glow, not a cut.
    """
    def shade(u, v):
        top, bottom = v, 1.0 - v
        left, right = u, 1.0 - u
        edge = min(top, bottom, left, right)

        dark = shadow * band(top, depth)
        side = ambient * shadow * max(band(left, depth), band(right, depth),
                                      band(bottom, depth))
        dark = max(dark, side)

        half = depth * light_depth / 2.0
        peak = rim_width + half
        lit = max(0.0, 1.0 - abs(bottom - peak) / half) if half > 0 else 0.0
        light = highlight * smoothstep(lit)

        if rim > 0.0 and edge < rim_width:
            dark += rim * (1.0 - edge / rim_width) ** 2

        net = dark - light
        if net >= 0.0:
            return 0.0, min(1.0, net)
        return 1.0, min(1.0, -net)

    return shade


def round_(depth, shadow, ambient, highlight, rim=0.0, rim_width=0.06,
           light_depth=0.5):
    """The same recess on a disc, for icons standing in for a portrait."""
    center = 0.5

    def shade(u, v):
        dx, dy = u - center, v - center
        distance = math.sqrt(dx * dx + dy * dy)
        if distance > 0.5 or distance <= 0.0001:
            return 0.0, 0.0
        r = distance / 0.5
        t = smoothstep(max(0.0, (r - (1.0 - depth)) / depth))
        vertical = dy / distance
        up = max(0.0, -vertical)
        down = max(0.0, vertical)
        dark = t * shadow * (ambient + (1.0 - ambient) * up)
        half = depth * light_depth / 2.0
        peak = 1.0 - rim_width - half
        lit = smoothstep(max(0.0, 1.0 - abs(r - peak) / half))
        light = lit * highlight * down ** 0.8
        if rim > 0.0:
            edge = max(0.0, (r - (1.0 - rim_width)) / rim_width)
            dark += rim * edge * edge
        net = dark - light
        if net >= 0.0:
            return 0.0, min(1.0, net)
        return 1.0, min(1.0, -net)

    return shade


def circle_mask():
    """A filled disc spanning the whole texture: the alpha mask that rounds a
    square icon off into a portrait."""
    def shade(u, v):
        dx, dy = u - 0.5, v - 0.5
        return 1.0, 1.0 if math.sqrt(dx * dx + dy * dy) <= 0.5 else 0.0

    return shade


# Three depths of the same cut. Small icons want Soft -- at 14px a hard bevel
# is most of the icon -- so that is what the suite defaults to; Deep and Carved
# are there for the bigger buttons.
STYLES = {
    "Soft":   dict(depth=0.30, shadow=0.55, ambient=0.35, highlight=0.30),
    "Deep":   dict(depth=0.28, shadow=0.85, ambient=0.40, highlight=0.50, rim=0.35),
    "Carved": dict(depth=0.16, shadow=1.00, ambient=0.45, highlight=0.70, rim=0.55,
                   rim_width=0.035),
}


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "../Textures"
    os.makedirs(target, exist_ok=True)
    for name, params in sorted(STYLES.items()):
        path = os.path.join(target, "IconDeboss%s.png" % name)
        write_png(path, render(square(**params)), SIZE, SIZE)
        print(path)
        path = os.path.join(target, "IconWell%s.png" % name)
        write_png(path, render(round_(**params)), SIZE, SIZE)
        print(path)
    path = os.path.join(target, "IconCircleMask.png")
    write_png(path, render(circle_mask()), SIZE, SIZE)
    print(path)


if __name__ == "__main__":
    main()
