#!/usr/bin/env python3
"""Generate the Commander_Casting portrait-ring artwork.

Six donut weights (thinnest first) sized as a proportion of the texture, a soft
additive halo, a tick bar, and the sweep's spark. All white so the addon can
vertex-tint them.
"""

import math
import os
import struct
import sys
import zlib

SIZE = 128
SS = 4                      # supersample factor per axis
OUTER = 0.485               # donut outer radius as a fraction of the width
RATIOS = [0.93, 0.88, 0.80, 0.71, 0.60, 0.46]   # inner radius / outer radius

# The spark at the head of the sweep, as fractions of the texture. Half-sizes:
# the core is the flat-alpha part, the fade is what runs past it. The addon
# mirrors EDGE_CORE and EDGE_FADE so it can size the quad from the ring band.
EDGE_CORE = 0.30            # half-length of the core -- maps to the band
EDGE_FADE = 0.06            # falloff past each end of the band
EDGE_WIDTH = 0.12           # half-width of the line
EDGE_WIDTH_FADE = 0.06


def write_png(path, pixels, width, height):
    raw = bytearray()
    for y in range(height):
        raw.append(0)                       # filter type 0 (None)
        row = pixels[y * width * 4:(y + 1) * width * 4]
        raw.extend(row)

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


def render(coverage, width=SIZE, height=SIZE):
    """coverage(x, y) -> 0..1 alpha, sampled at pixel centers with SSxSS AA."""
    pixels = bytearray(width * height * 4)
    step = 1.0 / SS
    offset = step / 2.0
    for py in range(height):
        for px in range(width):
            total = 0.0
            for sy in range(SS):
                y = py + offset + sy * step
                for sx in range(SS):
                    x = px + offset + sx * step
                    total += coverage(x, y)
            alpha = total / (SS * SS)
            index = (py * width + px) * 4
            pixels[index] = 255
            pixels[index + 1] = 255
            pixels[index + 2] = 255
            pixels[index + 3] = int(max(0.0, min(1.0, alpha)) * 255 + 0.5)
    return pixels


def render_rgba(shade, width=SIZE, height=SIZE):
    """shade(x, y) -> (value, alpha), value 0..1 dark..light, sampled with AA.

    Averaging premultiplied so a black edge and a white edge never bleed into
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
                y = py + offset + sy * step
                for sx in range(SS):
                    x = px + offset + sx * step
                    value, alpha = shade(x, y)
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


def deboss(depth, shadow, ambient, highlight, rim=0.0, rim_width=0.06,
           light_depth=1.0):
    """The inner shadow that presses the spell icon into the frame.

    Transparent through the middle and gathering toward the rim: dark where the
    light would be blocked (the top edge of a recess) and light where it would
    pool (the bottom edge). Drawn over the icon at the icon's own size, so the
    two are one disc.

    depth      how far in from the rim the shading reaches, as a fraction of it
    shadow     opacity at the darkest point of the rim
    ambient    share of the shadow that wraps the whole rim rather than the top
    highlight  opacity at the brightest point, opposite the shadow
    rim        an extra dark line hugging the very edge, all the way round --
               what makes the disc read as CUT into the frame rather than laid
               on it, since a real cut has a hard edge and a soft interior
    light_depth the highlight's share of that band. Below 1 it becomes a line
               along the bottom edge instead of a wash up the lower half, which
               is the difference between a lit rim and a glow
    """
    center = SIZE / 2.0
    radius = SIZE / 2.0

    def shade(x, y):
        dx, dy = x - center, y - center
        distance = math.sqrt(dx * dx + dy * dy)
        if distance > radius or distance <= 0.0001:
            return 0.0, 0.0
        r = distance / radius
        # 0 through the flat middle, 1 at the rim, eased so there is no ring
        t = max(0.0, (r - (1.0 - depth)) / depth)
        t = t * t * (3.0 - 2.0 * t)
        # Light from above: -1 straight up the disc, +1 straight down it
        vertical = dy / distance
        up = max(0.0, -vertical)
        down = max(0.0, vertical)
        dark = t * shadow * (ambient + (1.0 - ambient) * up)
        lit = t
        if light_depth < 1.0:
            # A line running just INSIDE the dark edge rather than under it.
            # Peaked, not ramped: on a real bevel the catch light is a stripe
            # with the cut's own shadow outboard of it, and stacking the two on
            # the same pixels is what made this read as a glow instead.
            half = depth * light_depth / 2.0
            peak = 1.0 - rim_width - half
            lit = max(0.0, 1.0 - abs(r - peak) / half)
            lit = lit * lit * (3.0 - 2.0 * lit)
        light = lit * highlight * down ** 0.8
        if rim > 0.0:
            edge = max(0.0, (r - (1.0 - rim_width)) / rim_width)
            dark += rim * edge * edge
        net = dark - light
        if net >= 0.0:
            return 0.0, min(1.0, net)
        return 1.0, min(1.0, -net)

    return shade


# The recess styles offered in the settings. Same shape throughout -- what
# changes is how deep the cut reads and how much of the rim carries it.
DEBOSS_STYLES = {
    # What shipped first: a shallow press, the icon still sitting near the surface
    "Soft":   dict(depth=0.34, shadow=0.62, ambient=0.25, highlight=0.38),
    # The same light, driven harder, with the catch light pulled back to a line
    "Deep":   dict(depth=0.34, shadow=0.95, ambient=0.35, highlight=0.65, rim=0.40,
                   light_depth=0.40),
    # A narrow bevel with a hard edge: an icon stamped into metal
    "Carved": dict(depth=0.16, shadow=1.0, ambient=0.35, highlight=0.85, rim=0.60,
                   rim_width=0.035, light_depth=0.55),
    # No light direction at all -- darkness closing in from every side, so the
    # icon reads as lying at the bottom of the socket rather than tilted in it
    "Well":   dict(depth=0.45, shadow=0.95, ambient=1.0, highlight=0.0, rim=0.4),
}


def donut(inner_ratio):
    center = SIZE / 2.0
    outer = SIZE * OUTER
    inner = outer * inner_ratio

    def coverage(x, y):
        dx, dy = x - center, y - center
        distance = math.sqrt(dx * dx + dy * dy)
        return 1.0 if inner <= distance <= outer else 0.0

    return coverage


def halo():
    """A soft donut for the feedback flash: bright on the rim, fading both ways."""
    center = SIZE / 2.0
    peak = SIZE * 0.36          # rim sits inside the frame so the bloom has room
    spread = SIZE * 0.12

    def coverage(x, y):
        dx, dy = x - center, y - center
        distance = math.sqrt(dx * dx + dy * dy)
        falloff = (distance - peak) / spread
        return math.exp(-falloff * falloff)

    return coverage


def tick():
    """A vertical bar with clear margins, so SetRotation never clips its ends."""
    center = SIZE / 2.0
    half_width = SIZE * 0.055
    half_length = SIZE * 0.35   # stays inside the inscribed circle when rotated

    def coverage(x, y):
        dx, dy = x - center, y - center
        return 1.0 if abs(dx) <= half_width and abs(dy) <= half_length else 0.0

    return coverage


def disc():
    """A filled circle spanning the whole texture: the alpha mask that rounds a
    spell icon off into a portrait.

    Full-bleed on purpose -- the addon sizes the quad to the ring's inner hole
    and the mask covers it exactly, so the icon is cut off right where the arc
    begins.
    """
    center = SIZE / 2.0
    radius = SIZE / 2.0

    def coverage(x, y):
        dx, dy = x - center, y - center
        return 1.0 if math.sqrt(dx * dx + dy * dy) <= radius else 0.0

    return coverage


def edge():
    """The sweep's spark: a bar that is flat across its core and fades out just
    past it, both radially and across its width.

    The addon sizes the quad so the core is exactly as long as the ring band is
    thick, which is the whole point of the shape -- the spark is cut off at the
    band and only the falloff spills over the rim. Fades rather than a hard cut,
    so the ends never read as a clipped stub.
    """
    center = SIZE / 2.0

    def ramp(distance, core, fade):
        if distance <= core:
            return 1.0
        if distance >= core + fade:
            return 0.0
        t = (distance - core) / fade
        return 1.0 - t * t * (3.0 - 2.0 * t)    # smoothstep: no lip at the cut

    def coverage(x, y):
        dx, dy = abs(x - center), abs(y - center)
        return (ramp(dy, SIZE * EDGE_CORE, SIZE * EDGE_FADE)
                * ramp(dx, SIZE * EDGE_WIDTH, SIZE * EDGE_WIDTH_FADE))

    return coverage


def main():
    target = sys.argv[1]
    os.makedirs(target, exist_ok=True)
    for index, ratio in enumerate(RATIOS, start=1):
        path = os.path.join(target, "Ring%d.png" % index)
        write_png(path, render(donut(ratio)), SIZE, SIZE)
        print("%s  inner ratio %.2f" % (path, ratio))
    write_png(os.path.join(target, "RingGlow.png"), render(halo()), SIZE, SIZE)
    write_png(os.path.join(target, "Tick.png"), render(tick()), SIZE, SIZE)
    write_png(os.path.join(target, "Edge.png"), render(edge()), SIZE, SIZE)
    write_png(os.path.join(target, "CircleMask.png"), render(disc()), SIZE, SIZE)
    for name, params in sorted(DEBOSS_STYLES.items()):
        path = os.path.join(target, "IconShade%s.png" % name)
        write_png(path, render_rgba(deboss(**params)), SIZE, SIZE)
        print(path)
    print("RingGlow.png, Tick.png, Edge.png, CircleMask.png")


if __name__ == "__main__":
    main()
