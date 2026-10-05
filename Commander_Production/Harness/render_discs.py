#!/usr/bin/env python3
"""Draw the radial boards from production_smoke.lua's dump.

    luajit  Harness/production_smoke.lua board.json
    python3 Harness/render_discs.py board.json board.svg [scale]
    qlmanage -t -s 1600 -o . board.svg board-2.svg board-3.svg board-4.svg

The rings, glows, masks, spark and wipe halves are the addon's own PNGs,
embedded and composited the way the client would: tinted by vertex colour,
turned by SetRotation, clipped by their mask textures, a Cooldown's swipe cut
to the wedge that remains. Spell icons are not on disk outside the client, so
each face is a flat tile -- one of them near white, because a white number on
a white icon is the case the shade under the countdown exists for. Every
position and size is the layout code's own output. Each board is drawn over a
strip of "world" running from snow to cave.
"""
import base64
import json
import math
import os
import sys

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0] + ".svg"
S = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0

ADDONS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAD, CAPTION = 30, 34
FACES = ["#f3ead0", "#7a4a9c", "#b5482f", "#2f6f8f", "#4d7a3a", "#c9a227"]

with open(src, encoding="utf-8") as fh:
    scenes = json.load(fh)["scenes"]

uris = {}


def uri(tex):
    """A data URI for one of the addon's own textures, or None for client art."""
    if tex not in uris:
        prefix = "Interface\\AddOns\\"
        path = os.path.join(ADDONS, *tex[len(prefix):].split("\\")) if tex.startswith(prefix) else None
        if path and os.path.exists(path):
            with open(path, "rb") as fh:
                uris[tex] = "data:image/png;base64," + base64.b64encode(fh.read()).decode("ascii")
        else:
            uris[tex] = None
    return uris[tex]


defs, body = [], []
tints = {}
serial = [0]


def new_id(prefix):
    serial[0] += 1
    return "%s%d" % (prefix, serial[0])


def tint(r, g, b):
    key = (round(r, 3), round(g, 3), round(b, 3))
    if key not in tints:
        tints[key] = new_id("t")
        defs.append('<filter id="%s" color-interpolation-filters="sRGB" x="0" y="0" width="1" height="1">'
                    '<feColorMatrix type="matrix" values="%g 0 0 0 0  0 %g 0 0 0  0 0 %g 0 0  0 0 0 1 0"/></filter>'
                    % (tints[key], key[0], key[1], key[2]))
    return tints[key]


def draw_scene(scene, top):
    items = sorted(scene["items"], key=lambda it: tuple(it["order"]))
    xs = [0, scene["w"]] + [it["cx"] - it["w"] / 2 for it in items] + [it["cx"] + it["w"] / 2 for it in items]
    ys = [0, -scene["h"]] + [it["cy"] - it["h"] / 2 for it in items] + [it["cy"] + it["h"] / 2 for it in items]
    minx, maxy = min(xs), max(ys)
    width = (max(xs) - minx) * S + PAD * 2
    height = (maxy - min(ys)) * S + PAD * 2

    def X(v):
        return (v - minx) * S + PAD

    def Y(v):
        return (maxy - v) * S + PAD + top + CAPTION

    world = new_id("w")
    defs.append('<linearGradient id="%s" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#e4eaf0"/>'
                '<stop offset="0.5" stop-color="#6b7a58"/><stop offset="1" stop-color="#17181c"/></linearGradient>' % world)
    body.append('<text x="%d" y="%.1f" font-family="Helvetica" font-size="15" fill="#ddd">%s</text>'
                % (PAD, top + 22, scene["caption"].replace("&", "&amp;")))
    body.append('<rect x="0" y="%.1f" width="%.1f" height="%.1f" fill="url(#%s)"/>' % (top + CAPTION, width, height, world))
    # The queue frame's own bounds, for reference
    body.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="#fff" stroke-opacity="0.25" '
                'stroke-dasharray="4 4"/>' % (X(0), Y(0), scene["w"] * S, scene["h"] * S))

    for it in items:
        cx, cy = X(it["cx"]), Y(it["cy"])
        w, h = it["w"] * S, it["h"] * S
        x, y = cx - w / 2, cy - h / 2
        if it["kind"] == "text":
            size = it["size"] * S
            body.append('<text x="%.1f" y="%.1f" text-anchor="middle" dominant-baseline="central" font-family="Georgia" '
                        'font-weight="bold" font-size="%.1f" fill="#fff" fill-opacity="%.3f" stroke="#000" stroke-width="%.1f" '
                        'paint-order="stroke">%s</text>' % (cx, cy, size, it["alpha"], S * 0.5, it["text"]))
            continue
        opacity = max(0.0, min(1.0, it["a"] * it["alpha"]))
        href = uri(it["tex"])
        if href:
            inner = ('<image href="%s" x="%.2f" y="%.2f" width="%.2f" height="%.2f" preserveAspectRatio="none" '
                     'filter="url(#%s)" opacity="%.3f"/>' % (href, x, y, w, h, tint(it["r"], it["g"], it["b"]), opacity))
        else:
            # A spell icon: a flat tile, picked by name so a board keeps its faces
            face = FACES[sum(map(ord, it["tex"])) % len(FACES)]
            inner = ('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" opacity="%.3f"/>'
                     % (x, y, w, h, face, opacity))
        if it.get("rot"):
            # SetRotation turns counterclockwise; SVG's y runs down, so its turn is clockwise
            inner = '<g transform="rotate(%.3f %.2f %.2f)">%s</g>' % (-math.degrees(it["rot"]), cx, cy, inner)
        if it["kind"] == "swipe":
            # What remains of the cooldown: from the sweep's edge clockwise round to twelve
            clip = new_id("c")
            reach = max(w, h)
            points = ["%.2f,%.2f" % (cx, cy)]
            start = it["elapsed"] * 360.0
            steps = max(2, int((360.0 - start) / 4))
            for i in range(steps + 1):
                theta = math.radians(start + (360.0 - start) * i / steps)
                points.append("%.2f,%.2f" % (cx + reach * math.sin(theta), cy - reach * math.cos(theta)))
            defs.append('<clipPath id="%s"><polygon points="%s"/></clipPath>' % (clip, " ".join(points)))
            inner = '<g clip-path="url(#%s)">%s</g>' % (clip, inner)
        mask = it.get("mask")
        if mask and uri(mask["tex"]):
            mid = new_id("m")
            mw, mh = mask["w"] * S, mask["h"] * S
            mx, my = X(mask["cx"]) - mw / 2, Y(mask["cy"]) - mh / 2
            defs.append('<mask id="%s" maskUnits="userSpaceOnUse" x="%.2f" y="%.2f" width="%.2f" height="%.2f">'
                        '<image href="%s" x="%.2f" y="%.2f" width="%.2f" height="%.2f" preserveAspectRatio="none"/></mask>'
                        % (mid, mx, my, mw, mh, uri(mask["tex"]), mx, my, mw, mh))
            inner = '<g mask="url(#%s)">%s</g>' % (mid, inner)
        if it.get("blend") == "ADD":
            inner = '<g style="mix-blend-mode:plus-lighter">%s</g>' % inner
        body.append(inner)
    return width, height + CAPTION


# One board per file keeps each thumbnail's aspect sane: board.svg, board-2.svg, ...
stem, ext = os.path.splitext(dst)
for index, scene in enumerate(scenes):
    del defs[:], body[:]
    tints.clear()
    total_w, top = draw_scene(scene, 0)
    # A square canvas: qlmanage crops a thumbnail to one
    total_w = top = max(total_w, top)
    out = dst if index == 0 else "%s-%d%s" % (stem, index + 1, ext)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
                 % (total_w, top, total_w, top))
        fh.write('<rect width="100%" height="100%" fill="#101114"/>')
        fh.write("<defs>%s</defs>%s</svg>" % ("".join(defs), "".join(body)))
    print("wrote %s" % out)
