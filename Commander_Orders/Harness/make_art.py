#!/usr/bin/env python3
"""Generate Commander Orders' own art: the arrow, its shadow, and the pins.

Why our own. TomTom's art cannot be copied (TomTom.toc says "All Rights
Reserved"; its modern theme is CC BY-NC), and the old Orders arrow borrowed
the minimap's stock corpse arrow (Interface\\Minimap\\MiniMap-DeadArrow),
which read as the death marker it is. Everything the
navigation HUD and the maps draw comes from this file instead, made the way
the rest of the suite makes its art (Commander_Plates/Harness/make_glows.py,
Commander_Casting/Harness/make_rings.py): stdlib Python, zlib + struct, RGBA8
PNG at power-of-two sizes, no dependencies.

White art, shading in the RGB. The addon tints every texture with
SetVertexColor, which MULTIPLIES -- so a pure white pixel takes the tint
exactly, a 0.8 grey takes a darker shade of it and a near-black rim stays near
black whatever the colour. That is how the arrow keeps its facets, its bevel
and its dark outline through any tint (Commander_PartyFrames/Harness/
make_dials.py does the same for its bands). Shape lives in alpha.

THE RULE THAT SHAPES EVERYTHING HERE. Every pixel with non-zero alpha lies
inside the inscribed circle: r <= side/2 - 2 px, measured to the pixel's FAR
corner, which also leaves the outer two pixel rows and columns fully
transparent. Nobody has yet confirmed in game whether Texture:SetRotation
turns the quad or only the texture coordinates (ASSUMPTIONS A4, probe P5). If
it turns the coordinates, the quad's corners sample outside the square, and
only what sits inside the inscribed circle survives every angle; a square
margin (the old "8 per cent" proposal) still clips at 45 degrees. The same
rule keeps the art safe under the 8-argument SetTexCoord rotation. The
generator asserts the rule on every texture before writing it, and again on
the file it wrote, decoded back from disk; --check repeats that on whatever is
on disk.

Orientation. Every directional texture points STRAIGHT UP (towards the top
edge) at rotation 0. SetRotation is counter-clockwise for positive radians,
which is the sense of GetPlayerFacing and of the bearing Geo computes, so the
runtime passes the relative angle straight through.

The textures and what the runtime needs to know about each:

  Arrow.png        256  the navigation arrow: a dart with a notched tail and
                        chamfered shoulders (sharp shoulders read as a three-
                        pointed boomerang at 45 and 135 degrees -- the tip has
                        to be the only sharp corner), a dark outline, a thin
                        lit bevel band inside it, and two facets meeting on the
                        centre ridge, lit from the upper left, darkening a
                        little towards the tail. Tip to tail it is 0.66 of the
                        quad and 0.53 across; its farthest point is
                        ARROW_REACH (0.405) from the centre, the radius it
                        sweeps as it turns. So the quad is the arrow's length
                        over 0.66: an 85 px quad draws a 56 px arrow, a 64 px
                        quad a 42 px one. The texture centre -- the pivot --
                        sits on the dart's centre of area (within 0.01 of the
                        width), so it spins in place instead of wobbling round
                        its tail.
  ArrowShadow.png  256  the same silhouette, swollen and softened outward.
                        White like everything else: tint it BLACK at about 0.6
                        alpha for a drop shadow, or with the arrow's colour at
                        low alpha for a glow. Same size and the same rotation
                        as the arrow; give it a fixed SCREEN-space offset
                        (about 1 right, 2 down), never a texture-space one, or
                        the shadow would swing round with the arrow.
  Arrived.png      256  a ring with a tick through it, drawn as geometry (D11:
                        never a font glyph), dark-outlined like the arrow.
  Ring.png         256  a ring at RING_RADIUS (0.39) of the width: a bright core
                        edged dark, in a soft halo either side, so it reads on
                        the pale world map as well as on dark ground. The NEAR
                        pulse and the focus ring round an active pin; pulse it
                        with SetScale or the quad size and alpha.
  Pin.png           64  a map pin: a bright domed dot inside a dark rim, so a
                        tinted pin reads on a pale map and on a dark minimap.
  PinEdge.png       64  a small solid chevron for the minimap rim, the arrow's
                        little brother; rotate it to the edge angle.
  Badge.png         64  a round badge for route-stop numbers: dark rim, a
                        bright ring, and a deeper fill so a number drawn on it
                        in a white outlined font stands out after tinting.
  Corpse.png        64  a tombstone with an engraved cross: the one marker that
                        must never be mistaken for a quest pin.

Fully transparent pixels carry the colour of the nearest drawn pixel rather
than black. The client filters straight (not premultiplied) alpha, so a white
glow next to transparent BLACK picks up a dark fringe when it is scaled or
mipmapped; bleeding the edge colour outward removes the fringe.

Traps:
  - New files need a full client restart before the game can load them;
    /reload is not enough.
  - Reference the files WITH the .png extension, as the rest of the suite does:
    "Interface\\AddOns\\Commander_Orders\\Textures\\Arrow.png".
  - Never crop the margin away with SetTexCoord to make the arrow bigger: the
    margin IS the rotation-safety contract. Make the quad bigger instead.

    python3 Harness/make_art.py                       write Textures/*.png
    python3 Harness/make_art.py --check               verify the files on disk
    python3 Harness/make_art.py --contact sheet.png   also write a review sheet
"""

import argparse
import collections
import math
import os
import random
import struct
import sys
import zlib

SS = 4                      # supersamples per axis
MARGIN = 2                  # px: the inscribed-circle rule's inset

# Everything below is in fractions of the texture's width, measured from its
# centre, y UP.

# --- the arrow ---------------------------------------------------------------
# A dart: tip, right shoulder, notch, left shoulder. Each shoulder is cut back
# by ARROW_CHAMFER along both of its edges, and the whole outline is then
# swollen by ARROW_ROUND, which rounds every convex corner (the tip included).
ARROW_TIP = 0.388
ARROW_SHOULDER_X = 0.265
ARROW_SHOULDER_Y = -0.255
ARROW_NOTCH = -0.165
ARROW_CHAMFER = 0.045
ARROW_ROUND = 0.017
SHADOW_SPREAD = 0.080       # how far the shadow reaches past the outline

# The arrow's shading, as luminance (the tint multiplies it)
RIM_WIDTH = 0.020           # the dark outline, inward from the edge
RIM_VALUE = 0.10
BEVEL_WIDTH = 0.030         # the lit band just inside the outline
FACE_LIT = 0.90             # the facet towards the light (left of the ridge)
FACE_SHADE = 0.70           # the facet away from it
BEVEL_LIT = 1.00            # the band where its edge faces the light
BEVEL_SHADE = 0.90          # the band where its edge faces away
TAIL_DARKEN = 0.10          # the faces lose this share from tip to tail
LIGHT = (-0.55, 0.835)      # towards the light: up and to the left


# ---------------------------------------------------------------------------
# PNG in and out
# ---------------------------------------------------------------------------

def write_png(path, pixels, width, height):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)                       # filter type 0 (None)
        raw.extend(pixels[y * stride:(y + 1) * stride])

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


def read_png(path):
    """Decode an RGBA8, non-interlaced PNG with any row filter:
    (width, height, pixels)."""
    with open(path, "rb") as handle:
        blob = handle.read()
    assert blob[:8] == b"\x89PNG\r\n\x1a\n", path
    pos, idat, width, height = 8, bytearray(), 0, 0
    while pos < len(blob):
        length = struct.unpack(">I", blob[pos:pos + 4])[0]
        tag = blob[pos + 4:pos + 8]
        data = blob[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", data)
            assert depth == 8 and colour == 6 and interlace == 0, (path, depth, colour)
        elif tag == b"IDAT":
            idat.extend(data)
        pos += 12 + length
    raw = zlib.decompress(bytes(idat))
    stride = width * 4
    pixels = bytearray(width * height * 4)
    prev = bytearray(stride)
    for y in range(height):
        kind = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b = prev[i]
            c = prev[i - 4] if i >= 4 else 0
            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        pixels[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, pixels


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(e0, e1, x):
    """Hermite step; e0 > e1 gives the falling step."""
    if e1 == e0:
        return 0.0 if x < e0 else 1.0
    t = clamp((x - e0) / (e1 - e0))
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return a + (b - a) * t


def toward(p, q, distance):
    dx, dy = q[0] - p[0], q[1] - p[1]
    length = math.hypot(dx, dy)
    return p[0] + dx / length * distance, p[1] + dy / length * distance


def dart(tip, shoulder_x, shoulder_y, notch, chamfer):
    """The dart outline, clockwise from the tip, shoulders chamfered."""
    t, n = (0.0, tip), (0.0, notch)
    right, left = (shoulder_x, shoulder_y), (-shoulder_x, shoulder_y)
    if chamfer <= 0.0:
        return [t, right, n, left]
    return [t, toward(right, t, chamfer), toward(right, n, chamfer), n,
            toward(left, n, chamfer), toward(left, t, chamfer)]


def polygon(px, py, pts):
    """Signed distance to a simple polygon (negative inside), and the unit
    normal pointing OUT of the shape from its nearest boundary point."""
    best, qx, qy = float("inf"), 0.0, 0.0
    inside = False
    ax, ay = pts[-1]
    for bx, by in pts:
        ex, ey = bx - ax, by - ay
        t = clamp(((px - ax) * ex + (py - ay) * ey) / (ex * ex + ey * ey))
        cx, cy = ax + ex * t, ay + ey * t
        dd = (px - cx) * (px - cx) + (py - cy) * (py - cy)
        if dd < best:
            best, qx, qy = dd, cx, cy
        if (ay > py) != (by > py) and px < ax + (py - ay) * ex / ey:
            inside = not inside
        ax, ay = bx, by
    dist = math.sqrt(best)
    if dist < 1e-9:
        return 0.0, 0.0, 1.0
    nx, ny = (px - qx) / dist, (py - qy) / dist
    if inside:
        return -dist, -nx, -ny
    return dist, nx, ny


def segment(px, py, ax, ay, bx, by):
    ex, ey = bx - ax, by - ay
    t = clamp(((px - ax) * ex + (py - ay) * ey) / (ex * ex + ey * ey))
    dx, dy = px - (ax + ex * t), py - (ay + ey * t)
    return math.sqrt(dx * dx + dy * dy)


def box(px, py, hw, hh):
    """Signed distance to an axis-aligned box centred on the origin."""
    qx, qy = abs(px) - hw, abs(py) - hh
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    return outside + min(max(qx, qy), 0.0)


def reach_of(pts, swell):
    return max(math.hypot(x, y) for x, y in pts) + swell


# ---------------------------------------------------------------------------
# Rendering and the rule
# ---------------------------------------------------------------------------

def render(size, shade, reach):
    """shade(x, y, px) -> (value, coverage) at a point x, y in fractions of
    the width from the centre, y UP; px is one pixel in those units.

    Supersampled SS x SS: coverage averaged, value averaged premultiplied, so
    a dark rim and a white face never bleed into grey where they meet. Pixels
    whose nearest point lies beyond `reach` are skipped as empty, and
    check_inscribed then proves the skip lost nothing that mattered."""
    pixels = bytearray(size * size * 4)
    unit = 1.0 / size
    step = 1.0 / SS
    samples = SS * SS
    half_diag = 0.5 * math.sqrt(2.0) * unit
    for row in range(size):
        for col in range(size):
            cx = (col + 0.5) * unit - 0.5
            cy = 0.5 - (row + 0.5) * unit
            if math.hypot(cx, cy) - half_diag > reach:
                continue
            weighted, total = 0.0, 0.0
            for sy in range(SS):
                y = 0.5 - (row + (sy + 0.5) * step) * unit
                for sx in range(SS):
                    x = (col + (sx + 0.5) * step) * unit - 0.5
                    value, cover = shade(x, y, unit)
                    if cover > 0.0:
                        weighted += value * cover
                        total += cover
            alpha = int(clamp(total / samples) * 255 + 0.5)
            if alpha == 0:
                continue
            level = int(clamp(weighted / total) * 255 + 0.5)
            index = (row * size + col) * 4
            pixels[index] = level
            pixels[index + 1] = level
            pixels[index + 2] = level
            pixels[index + 3] = alpha
    return bleed(pixels, size)


def edge_cover(d, px):
    """One supersample's coverage from its signed distance: a ramp one sample
    wide rather than a hard step, so SS x SS gives a smooth edge instead of
    seventeen grey levels."""
    return clamp(0.5 - d / (px / SS))


def bleed(pixels, size):
    """Give every fully transparent pixel the colour of the nearest drawn one
    (a breadth-first flood from the drawn pixels). Alpha is untouched."""
    queue = collections.deque()
    seen = bytearray(size * size)
    for i in range(size * size):
        if pixels[i * 4 + 3]:
            seen[i] = 1
            queue.append(i)
    if not queue:
        return pixels
    while queue:
        i = queue.popleft()
        row, col = divmod(i, size)
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            r, c = row + dr, col + dc
            if 0 <= r < size and 0 <= c < size:
                j = r * size + c
                if not seen[j]:
                    seen[j] = 1
                    pixels[j * 4:j * 4 + 3] = pixels[i * 4:i * 4 + 3]
                    queue.append(j)
    return pixels


def check_inscribed(name, pixels, size):
    """THE rule: no alpha beyond r = size/2 - MARGIN, measured to each pixel's
    farthest corner; and the outer two rows and columns empty. Returns the
    largest far-corner radius found."""
    limit = size / 2.0 - MARGIN
    worst = 0.0
    for row in range(size):
        for col in range(size):
            if pixels[(row * size + col) * 4 + 3] == 0:
                continue
            far = math.hypot(abs(col + 0.5 - size / 2.0) + 0.5,
                             abs(row + 0.5 - size / 2.0) + 0.5)
            assert far <= limit, "%s: alpha at (%d, %d), far corner r=%.2f > %.2f" % (
                name, col, row, far, limit)
            worst = max(worst, far)
    for i in range(size):
        for row, col in ((0, i), (size - 1, i), (i, 0), (i, size - 1),
                         (1, i), (size - 2, i), (i, 1), (i, size - 2)):
            assert pixels[(row * size + col) * 4 + 3] == 0, (name, "border", row, col)
    return worst


# ---------------------------------------------------------------------------
# The arrow and its shadow
# ---------------------------------------------------------------------------

ARROW_POLY = dart(ARROW_TIP, ARROW_SHOULDER_X, ARROW_SHOULDER_Y, ARROW_NOTCH, ARROW_CHAMFER)
ARROW_REACH = reach_of(ARROW_POLY, ARROW_ROUND)


def arrow_distance(x, y):
    d, nx, ny = polygon(x, y, ARROW_POLY)
    return d - ARROW_ROUND, nx, ny


def arrow(x, y, px):
    d, nx, ny = arrow_distance(x, y)
    cover = edge_cover(d, px)
    if cover <= 0.0:
        return 0.0, 0.0
    depth = -d
    # Two facets meeting on the ridge (x = 0), softened over a pixel or so so
    # the ridge is a crease, not a stair; darker towards the tail
    face = mix(FACE_SHADE, FACE_LIT, smoothstep(px * 1.2, -px * 1.2, x))
    face *= 1.0 - TAIL_DARKEN * clamp((ARROW_TIP - y) / (ARROW_TIP - ARROW_SHOULDER_Y))
    # The bevel band: brightest where its edge faces the light, peaking just
    # inside the outline and easing into the face
    lit = clamp(nx * LIGHT[0] + ny * LIGHT[1], -1.0, 1.0) * 0.5 + 0.5
    band = mix(BEVEL_SHADE, BEVEL_LIT, lit)
    inner = smoothstep(RIM_WIDTH + BEVEL_WIDTH, RIM_WIDTH + BEVEL_WIDTH * 0.3, depth)
    value = mix(face, band, inner)
    rim = smoothstep(RIM_WIDTH - px * 0.9, RIM_WIDTH + px * 0.9, depth)
    return mix(RIM_VALUE, value, rim), cover


def arrow_shadow(x, y, px):
    d, _, _ = arrow_distance(x, y)
    if d >= SHADOW_SPREAD:
        return 0.0, 0.0
    t = smoothstep(SHADOW_SPREAD, -0.012, d)
    return 1.0, t * t * (1.6 - 0.6 * t)


# ---------------------------------------------------------------------------
# Arrived and Ring
# ---------------------------------------------------------------------------

ARRIVED_OUTER = 0.455
ARRIVED_THICK = 0.075
ARRIVED_RIM = 0.020
TICK_WIDTH = 0.052          # half-width of the tick's stroke
TICK_POINTS = ((-0.190, 0.010), (-0.060, -0.135), (0.205, 0.150))


def arrived(x, y, px):
    r = math.hypot(x, y)
    ring_d = abs(r - (ARRIVED_OUTER - ARRIVED_THICK / 2.0)) - ARRIVED_THICK / 2.0
    (ax, ay), (bx, by), (cx, cy) = TICK_POINTS
    tick = min(segment(x, y, ax, ay, bx, by), segment(x, y, bx, by, cx, cy)) - TICK_WIDTH
    d = min(ring_d, tick)
    cover = edge_cover(d, px)
    if cover <= 0.0:
        return 0.0, 0.0
    value = mix(RIM_VALUE, 1.0, smoothstep(ARRIVED_RIM - px, ARRIVED_RIM + px, -d))
    return value, cover


RING_RADIUS = 0.390
RING_HALF = 0.030           # half the core band's thickness
RING_RIM = 0.012            # the dark hairline on each side of the core
RING_HALO = 0.060           # the soft glow's reach past the core
RING_HALO_ALPHA = 0.35


def ring(x, y, px):
    """A bright core edged dark on both sides, in a soft white halo. A pure
    glow vanishes on the pale world map and on snow; the dark hairlines carry
    it there, and the halo carries it on dark ground, where they disappear."""
    off = abs(math.hypot(x, y) - RING_RADIUS)
    core = edge_cover(off - RING_HALF, px)
    halo = 0.0
    if off < RING_HALF + RING_HALO:
        t = 1.0 - clamp((off - RING_HALF) / RING_HALO)
        halo = RING_HALO_ALPHA * t * t
    if core <= 0.0:
        return 1.0, halo
    # the core laid over the halo
    edge = smoothstep(RING_HALF - RING_RIM - px * 0.9, RING_HALF - RING_RIM + px * 0.9, off)
    value = mix(1.0, RIM_VALUE, edge)
    alpha = core + halo * (1.0 - core)
    return (value * core + halo * (1.0 - core)) / alpha, alpha


# ---------------------------------------------------------------------------
# The small markers (64 px)
# ---------------------------------------------------------------------------

PIN_RADIUS = 0.400
PIN_RIM = 0.095


def pin(x, y, px):
    r = math.hypot(x, y)
    cover = edge_cover(r - PIN_RADIUS, px)
    if cover <= 0.0:
        return 0.0, 0.0
    inner = PIN_RADIUS - PIN_RIM
    # a dome lit from the upper left, with a soft catch light
    dome = 1.0 - 0.22 * clamp(r / inner) ** 2
    catch = math.exp(-((x + 0.09) ** 2 + (y - 0.10) ** 2) / 0.006)
    value = clamp(dome + 0.15 * catch)
    rim = smoothstep(inner - px * 0.8, inner + px * 0.8, r)
    return mix(value, RIM_VALUE, rim), cover


EDGE_POLY = dart(0.360, 0.300, -0.215, -0.060, 0.040)
EDGE_ROUND = 0.030
EDGE_RIM = 0.075


def pin_edge(x, y, px):
    d, _, _ = polygon(x, y, EDGE_POLY)
    d -= EDGE_ROUND
    cover = edge_cover(d, px)
    if cover <= 0.0:
        return 0.0, 0.0
    face = mix(0.80, 1.0, smoothstep(px, -px, x))
    rim = smoothstep(EDGE_RIM - px * 0.8, EDGE_RIM + px * 0.8, -d)
    return mix(RIM_VALUE, face, rim), cover


BADGE_RADIUS = 0.440
BADGE_RIM = 0.060
BADGE_RING = 0.055
BADGE_FILL = 0.62


def badge(x, y, px):
    r = math.hypot(x, y)
    d = r - BADGE_RADIUS
    cover = edge_cover(d, px)
    if cover <= 0.0:
        return 0.0, 0.0
    depth = -d
    ring_in = smoothstep(BADGE_RIM - px * 0.8, BADGE_RIM + px * 0.8, depth)
    fill_in = smoothstep(BADGE_RIM + BADGE_RING - px * 0.8, BADGE_RIM + BADGE_RING + px * 0.8, depth)
    value = mix(RIM_VALUE, 1.0, ring_in)
    return mix(value, BADGE_FILL, fill_in), cover


# A tombstone: a slab with a round top, standing on a wider plinth
STONE_HALF = 0.200          # slab half-width; also the top's radius
STONE_TOP = 0.115           # centre of the round top
STONE_BOTTOM = -0.250
PLINTH_HALF = 0.262
PLINTH_TOP = -0.232
PLINTH_BOTTOM = -0.322
PLINTH_ROUND = 0.012
STONE_RIM = 0.068


def tombstone_distance(x, y):
    mid = (STONE_TOP + STONE_BOTTOM) / 2.0
    slab = box(x, y - mid, STONE_HALF, (STONE_TOP - STONE_BOTTOM) / 2.0)
    top = math.hypot(x, y - STONE_TOP) - STONE_HALF
    pmid = (PLINTH_TOP + PLINTH_BOTTOM) / 2.0
    plinth = box(x, y - pmid, PLINTH_HALF - PLINTH_ROUND,
                 (PLINTH_TOP - PLINTH_BOTTOM) / 2.0 - PLINTH_ROUND) - PLINTH_ROUND
    return min(slab, top, plinth)


def corpse(x, y, px):
    d = tombstone_distance(x, y)
    cover = edge_cover(d, px)
    if cover <= 0.0:
        return 0.0, 0.0
    face = 0.95 - 0.20 * clamp((0.30 - y) / 0.62)
    # the engraved cross
    cross = min(box(x, y - 0.050, 0.036, 0.165), box(x, y - 0.110, 0.115, 0.034))
    face = mix(0.28, face, smoothstep(-px * 0.8, px * 0.8, cross))
    rim = smoothstep(STONE_RIM - px * 0.8, STONE_RIM + px * 0.8, -d)
    return mix(RIM_VALUE, face, rim), cover


# ---------------------------------------------------------------------------
# The catalogue
# ---------------------------------------------------------------------------

AA = 0.010                  # reach slack for the anti-aliased edge

TEXTURES = [
    # name,          size, shade,        reach (fraction of the width)
    ("Arrow",        256, arrow,        ARROW_REACH + AA),
    ("ArrowShadow",  256, arrow_shadow, ARROW_REACH + SHADOW_SPREAD + AA),
    ("Arrived",      256, arrived,      ARRIVED_OUTER + AA),
    ("Ring",         256, ring,         RING_RADIUS + RING_HALF + RING_HALO + AA),
    ("Pin",           64, pin,          PIN_RADIUS + 2 * AA),
    ("PinEdge",       64, pin_edge,     reach_of(EDGE_POLY, EDGE_ROUND) + 2 * AA),
    ("Badge",         64, badge,        BADGE_RADIUS + 2 * AA),
    ("Corpse",        64, corpse,       math.hypot(PLINTH_HALF, PLINTH_BOTTOM) + 2 * AA),
]


# ---------------------------------------------------------------------------
# The contact sheet (review only; never shipped)
# ---------------------------------------------------------------------------

TINTS = {
    "green": (0.30, 1.00, 0.36),
    "yellow": (1.00, 0.84, 0.16),
    "red": (1.00, 0.26, 0.20),
    "ghost": (0.78, 0.86, 1.00),
}


class Sprite:
    """A texture the way the GPU sees it: STRAIGHT alpha, box-filtered mip
    levels, sampled bilinearly from the level nearest one texel per pixel. A
    dark fringe from transparent-black pixels would show here as it would in
    game."""

    def __init__(self, size, pixels):
        level = [(pixels[i * 4] / 255.0, pixels[i * 4 + 1] / 255.0,
                  pixels[i * 4 + 2] / 255.0, pixels[i * 4 + 3] / 255.0)
                 for i in range(size * size)]
        self.levels = [(size, level)]
        while size > 4:
            half = size // 2
            src, level = level, []
            for y in range(half):
                for x in range(half):
                    a = src[(y * 2) * size + x * 2]
                    b = src[(y * 2) * size + x * 2 + 1]
                    c = src[(y * 2 + 1) * size + x * 2]
                    d = src[(y * 2 + 1) * size + x * 2 + 1]
                    level.append(tuple((a[k] + b[k] + c[k] + d[k]) * 0.25 for k in range(4)))
            size = half
            self.levels.append((size, level))

    def sample(self, level, u, v):
        size, data = self.levels[level]
        x, y = u * size - 0.5, v * size - 0.5
        x0, y0 = int(math.floor(x)), int(math.floor(y))
        fx, fy = x - x0, y - y0
        out = [0.0, 0.0, 0.0, 0.0]
        for oy, wy in ((0, 1.0 - fy), (1, fy)):
            yy = min(max(y0 + oy, 0), size - 1)       # clamp, as the client does
            for ox, wx in ((0, 1.0 - fx), (1, fx)):
                xx = min(max(x0 + ox, 0), size - 1)
                p = data[yy * size + xx]
                w = wx * wy
                for k in range(4):
                    out[k] += p[k] * w
        return out


class Canvas:
    def __init__(self, width, height, colour=(0.20, 0.21, 0.23)):
        self.width, self.height = width, height
        self.rgb = [list(colour) for _ in range(width * height)]

    def fill(self, x0, y0, x1, y1, fn):
        for y in range(max(0, y0), min(self.height, y1)):
            for x in range(max(0, x0), min(self.width, x1)):
                self.rgb[y * self.width + x] = list(fn(x, y))

    def draw(self, sprite, cx, cy, size, angle=0.0, tint=(1, 1, 1), alpha=1.0):
        """Draw `sprite` as a size x size quad centred on (cx, cy), turned
        `angle` radians counter-clockwise, multiplied by `tint`."""
        ratio = sprite.levels[0][0] / float(size)
        level = 0
        while level + 1 < len(sprite.levels) and ratio >= 2.0:
            ratio /= 2.0
            level += 1
        ca, sa = math.cos(angle), math.sin(angle)
        half = size / 2.0
        reach = int(math.ceil(half * 1.42)) + 1
        for py in range(int(cy - reach), int(cy + reach) + 1):
            if py < 0 or py >= self.height:
                continue
            for px in range(int(cx - reach), int(cx + reach) + 1):
                if px < 0 or px >= self.width:
                    continue
                acc = [0.0, 0.0, 0.0, 0.0]
                for sy in (0.25, 0.75):
                    for sx in (0.25, 0.75):
                        ox = px + sx - cx
                        oy = cy - (py + sy)          # y up
                        u = ca * ox + sa * oy        # back into the quad's frame
                        v = -sa * ox + ca * oy
                        if abs(u) > half or abs(v) > half:
                            continue
                        s = sprite.sample(level, u / size + 0.5, 0.5 - v / size)
                        acc[0] += s[0] * s[3] * 0.25
                        acc[1] += s[1] * s[3] * 0.25
                        acc[2] += s[2] * s[3] * 0.25
                        acc[3] += s[3] * 0.25
                a = acc[3] * alpha
                if a <= 0.0:
                    continue
                dst = self.rgb[py * self.width + px]
                for k in range(3):
                    dst[k] = dst[k] * (1.0 - a) + acc[k] * alpha * tint[k]

    def save(self, path):
        pixels = bytearray(self.width * self.height * 4)
        for i, (r, g, b) in enumerate(self.rgb):
            pixels[i * 4] = int(clamp(r) * 255 + 0.5)
            pixels[i * 4 + 1] = int(clamp(g) * 255 + 0.5)
            pixels[i * 4 + 2] = int(clamp(b) * 255 + 0.5)
            pixels[i * 4 + 3] = 255
        write_png(path, pixels, self.width, self.height)


def noise_field(seed):
    rng = random.Random(seed)
    table = {}

    def lattice(ix, iy):
        if (ix, iy) not in table:
            table[(ix, iy)] = rng.random()
        return table[(ix, iy)]

    def value(x, y):
        ix, iy = int(math.floor(x)), int(math.floor(y))
        fx, fy = x - ix, y - iy
        sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a, b = lattice(ix, iy), lattice(ix + 1, iy)
        c, d = lattice(ix, iy + 1), lattice(ix + 1, iy + 1)
        top = a + (b - a) * sx
        return top + ((c + (d - c) * sx) - top) * sy

    return lambda x, y: 0.55 * value(x, y) + 0.3 * value(x * 2.1, y * 2.1) + 0.15 * value(x * 4.3, y * 4.3)


def backgrounds():
    noise = noise_field(5)

    def grass(x, y):
        t = noise(x / 23.0, y / 23.0)
        return 0.20 + 0.18 * t, 0.30 + 0.16 * t, 0.12 + 0.06 * t

    def snow(x, y):
        t = noise(x / 31.0, y / 31.0)
        return 0.70 + 0.25 * t, 0.74 + 0.22 * t, 0.80 + 0.18 * t

    return [lambda x, y: (0.07, 0.075, 0.09), lambda x, y: (0.86, 0.85, 0.81), grass, snow]


def contact_sheet(path, rendered):
    """Four panels -- dark, light, grass, snow -- each with:
      rows 1-3  the arrow tinted green / yellow / red, rotated 0, 45, 90, 135
                and 180 degrees on a 70 px quad (a 46 px arrow) over its
                shadow; then 50 and 88 px quads (33 and 58 px arrows);
                Arrived; Ring
      row 4     Pin and PinEdge at minimap sizes, Badge and Corpse at map
                sizes, then Corpse, Badge and Pin at 40 px
    and along the bottom every texture untinted at a readable size on dark and
    on light, with the arrow at its full 256 px."""
    sprites = {name: Sprite(size, pixels) for name, (size, pixels) in rendered.items()}
    cell = 84
    panel_w, panel_h = cell * 9 + 24, cell * 4 + 24
    width = panel_w * 2 + 12
    strip = 300
    height = panel_h * 2 + 12 + strip
    canvas = Canvas(width, height)

    def arrow_at(x, y, quad, deg, tint):
        canvas.draw(sprites["ArrowShadow"], x + 1, y + 2, quad, math.radians(deg), (0, 0, 0), 0.6)
        canvas.draw(sprites["Arrow"], x, y, quad, math.radians(deg), tint)

    for index, bg in enumerate(backgrounds()):
        ox = (index % 2) * (panel_w + 12)
        oy = (index // 2) * (panel_h + 12)
        canvas.fill(ox, oy, ox + panel_w, oy + panel_h, bg)
        for row, tint_name in enumerate(("green", "yellow", "red")):
            tint = TINTS[tint_name]
            y = oy + 12 + row * cell + cell // 2
            for col, deg in enumerate((0, 45, 90, 135, 180)):
                arrow_at(ox + 12 + col * cell + cell // 2, y, 70, deg, tint)
            x = ox + 12 + 5 * cell + cell // 2
            arrow_at(x, y, 50, 30, tint)
            arrow_at(x + cell, y, 88, -60, tint)
            canvas.draw(sprites["Arrived"], x + 2 * cell, y, 60, 0.0, tint)
            canvas.draw(sprites["Ring"], x + 3 * cell, y, 64, 0.0, tint)
        y = oy + 12 + 3 * cell + cell // 2
        x = ox + 12 + cell // 2
        for tint_name in ("green", "yellow", "red"):
            tint = TINTS[tint_name]
            canvas.draw(sprites["Pin"], x - 18, y - 16, 18, 0.0, tint)
            canvas.draw(sprites["Pin"], x + 10, y - 16, 26, 0.0, tint)
            canvas.draw(sprites["PinEdge"], x - 18, y + 16, 18, math.radians(-35), tint)
            canvas.draw(sprites["PinEdge"], x + 10, y + 16, 24, math.radians(120), tint)
            x += cell
        for tint_name in ("green", "yellow", "red"):
            canvas.draw(sprites["Badge"], x - 16, y, 24, 0.0, TINTS[tint_name])
            canvas.draw(sprites["Corpse"], x + 14, y, 28, 0.0, TINTS["ghost"])
            x += cell
        canvas.draw(sprites["Corpse"], x, y, 40, 0.0, TINTS["ghost"])
        canvas.draw(sprites["Badge"], x + cell, y, 40, 0.0, TINTS["yellow"])
        canvas.draw(sprites["Pin"], x + 2 * cell, y, 40, 0.0, TINTS["green"])

    # the bottom strip: untinted, on dark then on light
    y0 = panel_h * 2 + 12
    half_h = strip // 2
    canvas.fill(0, y0, 1000, y0 + half_h, lambda x, y: (0.12, 0.125, 0.14))
    canvas.fill(0, y0 + half_h, 1000, height, lambda x, y: (0.84, 0.83, 0.80))
    for band in range(2):
        y = y0 + band * half_h + half_h // 2
        x = 80
        for name in ("Arrow", "ArrowShadow", "Arrived", "Ring"):
            canvas.draw(sprites[name], x, y, 136, 0.0, (1, 1, 1))
            x += 146
        x -= 20
        for name in ("Pin", "PinEdge", "Badge", "Corpse"):
            canvas.draw(sprites[name], x, y, 64, 0.0, (1, 1, 1))
            x += 74
    canvas.fill(1000, y0, width, height, lambda x, y: (0.12, 0.125, 0.14) if x < 1290 else (0.84, 0.83, 0.80))
    canvas.draw(sprites["ArrowShadow"], 1145 + 3, y0 + strip // 2 + 6, 280, 0.0, (0, 0, 0), 0.6)
    canvas.draw(sprites["Arrow"], 1145, y0 + strip // 2, 280, 0.0, TINTS["green"])
    canvas.draw(sprites["ArrowShadow"], 1430 + 3, y0 + strip // 2 + 6, 280, math.radians(-45), (0, 0, 0), 0.6)
    canvas.draw(sprites["Arrow"], 1430, y0 + strip // 2, 280, math.radians(-45), TINTS["red"])
    canvas.save(path)


# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Textures"))
    parser.add_argument("--check", action="store_true", help="verify the files on disk only")
    parser.add_argument("--contact", help="also write a review contact sheet PNG here")
    args = parser.parse_args()

    rendered = {}
    for name, size, shade, reach in TEXTURES:
        assert size & (size - 1) == 0, (name, "power of two")
        path = os.path.join(args.out, name + ".png")
        if args.check:
            width, height, pixels = read_png(path)
            assert width == size and height == size, (name, width, height)
        else:
            pixels = render(size, shade, reach)
            check_inscribed(name, pixels, size)
            os.makedirs(args.out, exist_ok=True)
            write_png(path, pixels, size, size)
            width, height, pixels = read_png(path)      # what the client will read
        worst = check_inscribed(name, pixels, size)
        drawn = sum(1 for i in range(size * size) if pixels[i * 4 + 3])
        print("%-12s %3dx%-3d  far corner %6.2f px (limit %5.1f)  %5d drawn px" % (
            name, size, size, worst, size / 2.0 - MARGIN, drawn))
        rendered[name] = (size, pixels)
    print("all %d textures inside their inscribed circles" % len(TEXTURES))
    if args.contact:
        contact_sheet(args.contact, rendered)
        print("contact sheet:", args.contact)
    return 0


if __name__ == "__main__":
    sys.exit(main())
