#!/usr/bin/env python3
"""Draw the test board from arenaframes_render.lua's dump.

    luajit Commander_ArenaFrames/Harness/arenaframes_render.lua board.json
    python3 Commander_ArenaFrames/Harness/render_svg.py board.json board.svg [scale]

Not the game's art: icons are labelled squares, bar textures are flat fills
with a hint of gloss, the class sheet is a plain tile. What IS real is every
position, size, colour, alpha, font size, sweep fraction and piece of text --
the layout code's own output -- which is the half of "does it look right"
that a queue is not needed for. Open the SVG in a browser, or thumbnail it
with `qlmanage -t -s 1600 -o . board.svg`.
"""

import json
import os
import sys

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0] + ".svg"
SCALE = float(sys.argv[3]) if len(sys.argv) > 3 else 4.0

with open(src, encoding="utf-8") as fh:
    data = json.load(fh)

root = data["root"]
widgets = data["widgets"]

# The board plus a margin: DR icons hang off the right edge of the root.
PAD = 48
minl = min(w["l"] for w in widgets) - 4
maxr = max(w["l"] + w["w"] for w in widgets) + 4
mint = max(w["b"] + w["h"] for w in widgets) + 4
minb = min(w["b"] for w in widgets) - 4
W = (maxr - minl) * SCALE + PAD * 2
H = (mint - minb) * SCALE + PAD * 2


def X(v):
    return (v - minl) * SCALE + PAD


def Y(v):
    # WoW's y goes up; SVG's goes down
    return (mint - v) * SCALE + PAD


LAYER = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 4, "": 2}
FRAMES = {"Frame", "Button", "Cooldown"}


def order(w):
    depth = w["depth"] + (0.5 if w["kind"] in FRAMES else 0)
    # Every FontString on this board is created on OVERLAY; the mock does not
    # record a FontString's layer, so it is placed there by fiat.
    layer = 3 if w["kind"] == "FontString" else LAYER.get(w["layer"], 2)
    return (depth, layer, w["sub"])


widgets = sorted(enumerate(widgets), key=lambda iw: order(iw[1]) + (iw[0],))


def rgba(w, mul=1.0):
    r, g, b = w["r"], w["g"], w["bl"]
    if w["desat"]:
        grey = 0.3 * r + 0.59 * g + 0.11 * b
        r = g = b = grey
    a = w["a"] * w["alpha"] * mul
    return "rgb(%d,%d,%d)" % (int(r * 255), int(g * 255), int(b * 255)), max(0.0, min(1.0, a))


out = []
out.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % (W, H, W, H))
out.append('<defs><linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">'
           '<stop offset="0" stop-color="#fff" stop-opacity="0.28"/>'
           '<stop offset="0.45" stop-color="#fff" stop-opacity="0.06"/>'
           '<stop offset="0.5" stop-color="#000" stop-opacity="0.05"/>'
           '<stop offset="1" stop-color="#000" stop-opacity="0.25"/></linearGradient>'
           '<linearGradient id="spark" x1="0" y1="0" x2="1" y2="0">'
           '<stop offset="0" stop-color="#fff" stop-opacity="0"/>'
           '<stop offset="0.5" stop-color="#fff" stop-opacity="0.95"/>'
           '<stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient></defs>')
# A slab of "world" behind the board, so alpha reads as it would in a game.
out.append('<rect x="0" y="0" width="%d" height="%d" fill="#5a6b4c"/>' % (W, H))
out.append('<rect x="0" y="0" width="%d" height="%d" fill="url(#gloss)" opacity="0.5"/>' % (W, H))


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def strip_codes(t):
    import re
    return re.sub(r"\|c%s" % "[0-9a-fA-F]{8}", "", t).replace("|r", "")


for _, w in widgets:
    x, y, ww, hh = X(w["l"]), Y(w["b"] + w["h"]), w["w"] * SCALE, w["h"] * SCALE
    kind, tex = w["kind"], w["tex"]
    if kind == "Texture":
        fill, a = rgba(w)
        if tex.endswith("WHITE8X8"):
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" fill-opacity="%.3f"/>' % (x, y, ww, hh, fill, a))
        elif "Textures\\Bar" in tex or "UI-StatusBar" in tex:
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" fill-opacity="%.3f"/>' % (x, y, ww, hh, fill, a))
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="url(#gloss)" opacity="%.3f"/>' % (x, y, ww, hh, a))
        elif "Interface\\Icons\\" in tex or "\\Icons\\" in tex:
            name = tex.split("\\")[-1].replace("INV_", "").replace("Spell_", "").replace("Ability_", "")
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#6d5a3a" fill-opacity="%.3f"/>' % (x, y, ww, hh, a))
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" fill-opacity="%.3f"/>' % (x, y, ww, hh, fill, a * 0.55))
            fs = max(6, min(hh * 0.22, 11))
            out.append('<text x="%.1f" y="%.1f" font-size="%.1f" fill="#fff" fill-opacity="0.55" font-family="Helvetica" text-anchor="middle">%s</text>'
                       % (x + ww / 2, y + hh * 0.55, fs, esc(name[:12])))
        elif "CHARACTERCREATE" in tex:
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#3d4a6b" fill-opacity="%.3f"/>' % (x, y, ww, hh, a))
            out.append('<text x="%.1f" y="%.1f" font-size="%.1f" fill="#fff" fill-opacity="0.6" font-family="Helvetica" text-anchor="middle">class</text>'
                       % (x + ww / 2, y + hh * 0.6, max(6, hh * 0.22)))
        elif "Spark" in tex:
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="url(#spark)" opacity="%.3f"/>' % (x, y, ww, hh, a))
        elif "Deboss" in tex or "Well" in tex or "Mask" in tex:
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="#000" stroke-opacity="0.35" stroke-width="%.1f"/>'
                       % (x + 0.5, y + 0.5, ww - 1, hh - 1, SCALE * 0.6))
        else:
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" fill-opacity="%.3f"/>' % (x, y, ww, hh, fill, a * 0.8))
    elif kind == "Cooldown" and w.get("cd"):
        start, dur, now = w["cd"]
        elapsed = max(0.0, min(1.0, (now - start) / dur if dur > 0 else 1.0))
        remaining = 1.0 - elapsed
        if remaining > 0.001:
            import math
            cx, cy, r = x + ww / 2, y + hh / 2, math.hypot(ww, hh) / 2
            a0 = -math.pi / 2 + 2 * math.pi * elapsed
            a1 = -math.pi / 2 + 2 * math.pi
            steps = 24
            pts = ["%.1f,%.1f" % (cx, cy)]
            for i in range(steps + 1):
                t = a0 + (a1 - a0) * i / steps
                pts.append("%.1f,%.1f" % (cx + r * math.cos(t), cy + r * math.sin(t)))
            out.append('<clipPath id="c%d"><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f"/></clipPath>' % (id(w) % 100000, x, y, ww, hh))
            out.append('<polygon points="%s" fill="#000" fill-opacity="0.62" clip-path="url(#c%d)"/>' % (" ".join(pts), id(w) % 100000))
    elif kind == "FontString":
        text = strip_codes(w["text"])
        if not text:
            continue
        fill, a = rgba(w)
        fs = w["font"] * SCALE
        just = w["just"]
        if just == "end":
            tx, anchor = x + ww, "end"
        elif just == "start":
            tx, anchor = x, "start"
        else:
            tx, anchor = x + ww / 2, "middle"
        ty = y + hh / 2 + fs * 0.36
        out.append('<text x="%.1f" y="%.1f" font-size="%.1f" font-family="Helvetica" font-weight="bold" text-anchor="%s" '
                   'fill="%s" fill-opacity="%.3f" stroke="#000" stroke-width="%.1f" paint-order="stroke" stroke-linejoin="round">%s</text>'
                   % (tx, ty, fs, anchor, fill, a, SCALE * 0.7, esc(text)))

out.append("</svg>")
with open(dst, "w", encoding="utf-8") as fh:
    fh.write("\n".join(out))
print("wrote", dst, "(%dx%d)" % (W, H))
