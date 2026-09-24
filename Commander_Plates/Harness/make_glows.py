#!/usr/bin/env python3
"""Generate the radial plate's target-glow art: ten styles.

Every texture shares one geometry, which the addon mirrors
(CommanderPlatesRadial.lua, GLOW_BASE / GLOW_REACH):

  GLOW_BASE   the disc's edge, as a fraction of the texture's width. The
              glow rises from here; inside it the art is dark, because the
              disc sits there.
  GLOW_REACH  where every style has faded to NOTHING. A window forces alpha
              to zero from GLOW_FADE out to GLOW_REACH, well inside the
              texture's own edge -- the old RingGlow.png still had alpha at
              its border, so the glow ended in a hard square.

The margin beyond GLOW_REACH is fully transparent, which also makes the art
safe to spin with Texture:SetRotation (a rotated quad samples past its edge
at the corners; clamping a transparent margin smears nothing).

All white; the addon tints with the glow colour. Shape lives in alpha.

    python3 Harness/make_glows.py
"""
import math
import os
import random
import struct
import zlib

SIZE = 256
GLOW_BASE = 0.28
GLOW_FADE = 0.40
GLOW_REACH = 0.47
TAU = math.pi * 2


def write_png(path, alpha_rows):
    raw = bytearray()
    for row in alpha_rows:
        raw.append(0)
        for a in row:
            raw.extend((255, 255, 255, a))

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


# --- shared helpers --------------------------------------------------------

def smooth(e0, e1, x):
    if e1 == e0:
        return 0.0 if x < e0 else 1.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def window(r):
    """1 inside, falling smoothly to exactly 0 at GLOW_REACH."""
    return 1.0 - smooth(GLOW_FADE, GLOW_REACH, r)


def rise(r, soft=0.025):
    """0 well inside the disc, 1 from its edge out."""
    return smooth(GLOW_BASE - soft, GLOW_BASE, r)


def falloff(r, scale):
    d = max(0.0, r - GLOW_BASE)
    return math.exp(-d / scale)


def band(r, at, width):
    d = (r - at) / width
    return math.exp(-d * d)


def angdiff(a, b):
    d = (a - b) % TAU
    return d - TAU if d > math.pi else d


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    l2 = vx * vx + vy * vy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / l2))
    dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return math.sqrt(dx * dx + dy * dy)


class Noise:
    """Smooth value noise on a periodic-in-x lattice (x wraps at `period`)."""

    def __init__(self, seed, period):
        self.rng = random.Random(seed)
        self.period = period
        self.table = {}

    def lattice(self, ix, iy):
        key = (ix % self.period, iy)
        if key not in self.table:
            self.table[key] = self.rng.random()
        return self.table[key]

    def __call__(self, x, y):
        ix, iy = math.floor(x), math.floor(y)
        fx, fy = x - ix, y - iy
        sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a = self.lattice(ix, iy)
        b = self.lattice(ix + 1, iy)
        c = self.lattice(ix, iy + 1)
        d = self.lattice(ix + 1, iy + 1)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy

    def fbm(self, x, y, octaves=4):
        total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
        for _ in range(octaves):
            total += amp * self((x * freq), y * freq)
            norm += amp
            amp *= 0.5
            freq *= 2
        return total / norm


# --- the styles -----------------------------------------------------------
# Each is f(x, y, r, a) -> alpha 0..1, with x/y in texture widths from the
# centre (y up), r the radius and a the angle clockwise from twelve.

def soft(x, y, r, a):
    return rise(r) * (0.75 * falloff(r, 0.028) + 0.35 * falloff(r, 0.06))


def ember():
    noise = Noise(11, 24)

    def f(x, y, r, a):
        u = a / TAU * 24
        tongue = noise.fbm(u, (r - GLOW_BASE) * 18 - 0.0, 3)
        length = 0.025 + 0.07 * tongue ** 2
        flame = falloff(r, length) * (0.6 + 0.6 * tongue)
        return rise(r) * min(1.0, 0.45 * falloff(r, 0.02) + flame)
    return f


def runic():
    rng = random.Random(7)
    segments = []
    count = 16
    rr = GLOW_BASE + 0.075
    for k in range(count):
        th = k / count * TAU
        cx, cy = math.sin(th) * rr, math.cos(th) * rr
        # tangent and normal at this rune
        tx, ty = math.cos(th), -math.sin(th)
        nx, ny = math.sin(th), math.cos(th)
        h, w = 0.026, 0.012
        # a stave, and two or three strokes off it
        strokes = [((0, -h), (0, h))]
        for _ in range(rng.choice((2, 3))):
            p0 = (0, rng.uniform(-h, h))
            p1 = (rng.choice((-w, w)), p0[1] + rng.uniform(-h * 0.8, h * 0.8))
            strokes.append((p0, p1))
        for (u0, v0), (u1, v1) in strokes:
            ax, ay = cx + tx * u0 + nx * v0, cy + ty * u0 + ny * v0
            bx, by = cx + tx * u1 + nx * v1, cy + ty * u1 + ny * v1
            segments.append((ax, ay, bx, by))

    def f(x, y, r, a):
        glyph = 0.0
        if abs(r - rr) < 0.045:
            d = min(seg_dist(x, y, *s) for s in segments)
            glyph = math.exp(-(d / 0.0045) ** 2) + 0.35 * math.exp(-(d / 0.012) ** 2)
        ring = band(r, GLOW_BASE + 0.025, 0.006) + 0.5 * band(r, GLOW_BASE + 0.125, 0.004)
        return rise(r) * min(1.0, glyph + 0.8 * ring + 0.35 * falloff(r, 0.03))
    return f


def arcane(x, y, r, a):
    inner = band(r, GLOW_BASE + 0.022, 0.006)
    outer = band(r, GLOW_BASE + 0.085, 0.005)
    # motes on a spiral between the two rings
    motes = 0.0
    for k in range(3):
        phase = (a / TAU * 9 + k / 3.0) % 1.0
        target = GLOW_BASE + 0.03 + phase * 0.05
        ang = abs(((a * 9 / TAU + k / 3.0) % 1.0) - 0.5)
        motes += band(r, target, 0.008) * math.exp(-(ang / 0.08) ** 2)
    bloom = 0.4 * falloff(r, 0.035)
    return rise(r) * min(1.0, inner + 0.8 * outer + 0.8 * motes + bloom)


def radiant():
    rng = random.Random(3)
    rays = [(k / 32 * TAU + rng.uniform(-0.03, 0.03), rng.uniform(0.04, 0.12), rng.uniform(0.012, 0.03))
            for k in range(32)]

    def f(x, y, r, a):
        light = 0.0
        for th, length, width in rays:
            d = abs(angdiff(a, th)) * r
            taper = width * (1 - min(1.0, (r - GLOW_BASE) / length))
            if taper > 0:
                light = max(light, math.exp(-(d / max(taper, 1e-4)) ** 2) * falloff(r, length * 0.8))
        return rise(r) * min(1.0, 0.5 * falloff(r, 0.025) + light)
    return f


def frost():
    arms = 12

    def shard(x, y, r, a, th, length, width):
        d_along = r - GLOW_BASE
        if d_along < 0 or d_along > length:
            return 0.0
        half = width * (1 - d_along / length)
        d = abs(angdiff(a, th)) * r
        return smooth(half, half * 0.6, d)

    def f(x, y, r, a):
        ice = 0.0
        for k in range(arms):
            th = k / arms * TAU
            long_arm = k % 2 == 0
            length = 0.13 if long_arm else 0.07
            ice = max(ice, shard(x, y, r, a, th, length, 0.018 if long_arm else 0.012))
            if long_arm:
                # two side barbs, the snowflake's branches
                for side in (-1, 1):
                    bx0 = math.sin(th) * (GLOW_BASE + 0.05)
                    by0 = math.cos(th) * (GLOW_BASE + 0.05)
                    bth = th + side * 0.55
                    bx1 = bx0 + math.sin(bth) * 0.035
                    by1 = by0 + math.cos(bth) * 0.035
                    d = seg_dist(x, y, bx0, by0, bx1, by1)
                    ice = max(ice, math.exp(-(d / 0.004) ** 2))
        rim = band(r, GLOW_BASE + 0.012, 0.006)
        return rise(r) * min(1.0, ice * 0.95 + 0.6 * rim + 0.3 * falloff(r, 0.03))
    return f


def void():
    noise = Noise(29, 16)

    def f(x, y, r, a):
        swirl = a / TAU * 16 + (r - GLOW_BASE) * 40
        smoke = noise.fbm(swirl, (r - GLOW_BASE) * 22, 4)
        wisps = smooth(0.45, 0.8, smoke)
        body = falloff(r, 0.06) * (0.25 + 0.95 * wisps)
        return rise(r) * min(1.0, body + 0.3 * falloff(r, 0.018))
    return f


def halo(x, y, r, a):
    ring = band(r, GLOW_BASE + 0.03, 0.007)
    wide = 0.35 * falloff(r, 0.05)
    flare = 0.0
    for k in range(8):
        th = k / 8 * TAU
        length = 0.16 if k % 2 == 0 else 0.08
        d = abs(angdiff(a, th)) * r
        flare = max(flare, math.exp(-(d / 0.004) ** 2) * falloff(r, length * 0.5))
    return rise(r) * min(1.0, ring + wide + flare)


def sigil():
    nodes = 8
    rr = GLOW_BASE + 0.06
    pts = [(math.sin(k / nodes * TAU) * rr, math.cos(k / nodes * TAU) * rr) for k in range(nodes)]
    # an eight-pointed star drawn between the nodes, outside the disc only
    star = [(pts[k], pts[(k + 3) % nodes]) for k in range(nodes)]

    def f(x, y, r, a):
        orb = 0.0
        for px, py in pts:
            d = math.hypot(x - px, y - py)
            orb = max(orb, math.exp(-(d / 0.011) ** 2) + 0.5 * math.exp(-(d / 0.025) ** 2))
        lines = 0.0
        if r > GLOW_BASE:
            d = min(seg_dist(x, y, a0[0], a0[1], b0[0], b0[1]) for a0, b0 in star)
            lines = 0.7 * math.exp(-(d / 0.0035) ** 2)
        ring = band(r, rr, 0.004) * 0.8 + band(r, GLOW_BASE + 0.012, 0.005) * 0.6
        return rise(r) * min(1.0, orb + lines + ring + 0.25 * falloff(r, 0.04))
    return f


def storm():
    rng = random.Random(41)
    segments = []

    def bolt(th, r0, length, depth):
        steps = 6
        px, py = math.sin(th) * r0, math.cos(th) * r0
        ang = th
        for i in range(steps):
            ang += rng.uniform(-0.45, 0.45)
            step = length / steps
            nx, ny = px + math.sin(ang) * step, py + math.cos(ang) * step
            segments.append((px, py, nx, ny, depth))
            if depth < 1 and rng.random() < 0.35:
                bolt(ang + rng.choice((-0.8, 0.8)) * 0.6, math.hypot(nx, ny), length * 0.45, depth + 1)
            px, py = nx, ny

    for k in range(10):
        bolt(k / 10 * TAU + rng.uniform(-0.2, 0.2), GLOW_BASE + 0.005, rng.uniform(0.07, 0.13), 0)

    def f(x, y, r, a):
        arc = 0.0
        if r < GLOW_BASE + 0.16:
            for ax, ay, bx, by, depth in segments:
                d = seg_dist(x, y, ax, ay, bx, by)
                w = 0.0058 / (1 + 0.6 * depth)
                arc = max(arc, math.exp(-(d / w) ** 2) + 0.3 * math.exp(-(d / (w * 4)) ** 2))
        crackle = band(r, GLOW_BASE + 0.01, 0.006) * (0.6 + 0.4 * math.sin(a * 37) ** 2)
        return rise(r) * min(1.0, arc + crackle + 0.3 * falloff(r, 0.03))
    return f


STYLES = [
    ("GlowSoft", soft),
    ("GlowEmber", ember()),
    ("GlowRunic", runic()),
    ("GlowArcane", arcane),
    ("GlowRadiant", radiant()),
    ("GlowFrost", frost()),
    ("GlowVoid", void()),
    ("GlowHalo", halo),
    ("GlowSigil", sigil()),
    ("GlowStorm", storm()),
]


def render(fn):
    rows = []
    for py in range(SIZE):
        row = []
        y = 0.5 - (py + 0.5) / SIZE
        for px in range(SIZE):
            x = (px + 0.5) / SIZE - 0.5
            r = math.hypot(x, y)
            if r >= GLOW_REACH:
                row.append(0)
                continue
            a = math.atan2(x, y) % TAU
            v = fn(x, y, r, a) * window(r)
            row.append(int(round(255 * max(0.0, min(1.0, v)))))
        rows.append(row)
    return rows


def main():
    target = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Textures")
    for name, fn in STYLES:
        rows = render(fn)
        # The whole point: nothing on the texture's edge
        edge = max(max(rows[0]), max(rows[-1]), max(r[0] for r in rows), max(r[-1] for r in rows))
        assert edge == 0, (name, edge)
        write_png(os.path.join(target, name + ".png"), rows)
        print(name, "ok")


if __name__ == "__main__":
    main()
