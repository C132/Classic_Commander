#!/usr/bin/env python3
"""Draw the Spellbook window from spellbook_render.lua's dump.

    python3 Commander_Spellbook/Harness/render_svg.py book.json book.svg [scale]
    qlmanage -t -s 1600 -o . book.svg      # a PNG to look at

Not the game's art: icons are labelled squares, the dialog border is a flat
frame, backdrops are their recorded colours. What IS real is every position,
size, colour and string -- the layout code's own output. Text inside a scroll
frame is clipped to its viewport, as the client clips it. Cast buttons (the
secure overlays pinned over icons) are drawn as dashed cyan outlines so their
placement can be checked against what they cover.

qlmanage crops a non-square SVG to a square, so the canvas is made square.
"""

import json
import re
import sys

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else src.rsplit(".", 1)[0] + ".svg"
SCALE = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0

data = json.load(open(src, encoding="utf-8"))
rl, rb, rw, rh = data["root"]
PAD = 24
W = rw * SCALE + PAD * 2
H = rh * SCALE + PAD * 2
SIDE = max(W, H)


def X(v):
    return (v - rl) * SCALE + PAD


def Y(v):
    return (rb + rh - v) * SCALE + PAD


LAYER = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 9}


def order(w):
    # The client's order: frame level, then (inside a frame) its backdrop,
    # then its regions by layer and sublevel, then creation order
    if w["kind"] in ("Texture", "FontString"):
        layer = 3 if w["kind"] == "FontString" else LAYER.get(w["layer"], 2)
    else:
        layer = -1
    return (w["level"], layer, w["sub"], w["i"])


def rgb(c, mul=1.0):
    return "rgb(%d,%d,%d)" % tuple(int(max(0, min(1, v)) * 255) for v in c[:3])


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def spans(text, base):
    """Inline |cAARRGGBB ... |r as tspans; |T...|t (coin icons) as a dot."""
    text = re.sub(r"\|T.*?\|t", "●", text)
    out, color = [], base
    pos = 0
    for m in re.finditer(r"\|c([0-9a-fA-F]{8})|\|r", text):
        if m.start() > pos:
            out.append((text[pos:m.start()], color))
        color = ("#" + m.group(1)[2:]) if m.group(1) else base
        pos = m.end()
    if pos < len(text):
        out.append((text[pos:], color))
    return out


svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % (SIDE, SIDE, SIDE, SIDE)]
svg.append('<rect width="%d" height="%d" fill="#3b4636"/>' % (SIDE, SIDE))
svg.append("<defs>")
for i, (l, b, w, h) in enumerate(data["clips"], start=1):
    svg.append('<clipPath id="clip%d"><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f"/></clipPath>'
               % (i, X(l), Y(b + h), w * SCALE, h * SCALE))
svg.append("</defs>")
# The window's own floor and the dialog border the sheet draws
svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#17171a" stroke="#8a7a55" stroke-width="%.1f" rx="6"/>'
           % (X(rl), Y(rb + rh), rw * SCALE, rh * SCALE, 3 * SCALE))

widgets = sorted(data["widgets"], key=order)
for w in widgets:
    if w["layer"] == "HIGHLIGHT":
        continue
    x, y, ww, hh = X(w["l"]), Y(w["b"] + w["h"]), w["w"] * SCALE, w["h"] * SCALE
    clip = (' clip-path="url(#clip%d)"' % w["clip"]) if w["clip"] else ""
    c = w["color"]
    if w["cast"]:
        svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="#3fe0ff" '
                   'stroke-width="1.2" stroke-dasharray="3,2"/>' % (x, y, ww, hh))
        continue
    if w["backdrop"] and w["bd"][:3] != [1.0, 1.0, 1.0]:
        # (a white tint is a textured backdrop -- the dialog stone -- whose
        # art the dump does not carry; the floor drawn first stands in)
        bd, bdb = w["bd"], w["bdb"]
        svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" fill-opacity="%.2f" '
                   'stroke="%s" stroke-width="%.1f" rx="3"%s/>'
                   % (x, y, ww, hh, rgb(bd), bd[3], rgb(bdb), 1.2 * SCALE, clip))
    if w["kind"] == "Texture":
        tex = w["tex"]
        a = c[3] * w["alpha"]
        if not tex:
            continue
        if tex.endswith("WHITE8X8") or tex == "COLOR":
            svg.append('<g%s><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" fill-opacity="%.3f"/></g>'
                       % (clip, x, y, ww, hh, rgb(c), a))
        elif "Icons" in tex:
            name = tex.split("\\")[-1][:10]
            fill = "#555" if w["desat"] else "#7a5a2e"
            svg.append('<g%s><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" fill-opacity="%.2f" '
                       'stroke="#000" stroke-opacity="0.6"/>' % (clip, x, y, ww, hh, fill, a))
            svg.append('<text x="%.1f" y="%.1f" font-size="%.1f" fill="#fff" fill-opacity="0.6" font-family="Helvetica" '
                       'text-anchor="middle">%s</text></g>' % (x + ww / 2, y + hh * 0.62, max(5, hh * 0.3), esc(name)))
        elif "DialogBox-Header" in tex:
            svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#2a2418" stroke="#8a7a55" rx="4"/>'
                       % (x + ww * 0.25, y + hh * 0.2, ww * 0.5, hh * 0.45))
        elif "SizeGrabber" in tex:
            svg.append('<path d="M%.1f %.1f L%.1f %.1f L%.1f %.1f Z" fill="#aaa" fill-opacity="0.6"/>'
                       % (x + ww, y, x + ww, y + hh, x, y + hh))
    elif w["kind"] == "FontString":
        text = w["text"]
        if not text:
            continue
        size = w["font"] * SCALE
        just = w["just"] or "LEFT"
        if just == "RIGHT":
            tx, anchor = x + ww, "end"
        elif just == "CENTER":
            tx, anchor = x + ww / 2, "middle"
        else:
            tx, anchor = x, "start"
        ty = y + hh / 2 + size * 0.36
        base = rgb(c)
        parts = "".join('<tspan fill="%s">%s</tspan>' % (col, esc(t)) for t, col in spans(text, base))
        svg.append('<g%s><text x="%.1f" y="%.1f" font-size="%.1f" font-family="Helvetica" text-anchor="%s" '
                   'fill="%s">%s</text></g>' % (clip, tx, ty, size, anchor, base, parts))
    elif w["kind"] == "Button" and "UIPanelButtonTemplate" in (w["tmpl"] or ""):
        # A panel button: the template's face is not recorded, so draw one
        svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#5a1010" stroke="#c9a85a" '
                   'stroke-width="1" rx="3"%s/>' % (x, y, ww, hh, clip))
        if w["text"]:
            svg.append('<text x="%.1f" y="%.1f" font-size="%.1f" font-family="Helvetica" text-anchor="middle" '
                       'fill="#ffd100"%s>%s</text>' % (x + ww / 2, y + hh / 2 + 3.6 * SCALE, 10 * SCALE, clip, esc(w["text"])))
    elif w["kind"] == "Button" and w["text"] and not w["tmpl"]:
        # A plain button with a label (the toolbar's filters)
        svg.append('<g%s><text x="%.1f" y="%.1f" font-size="%.1f" font-family="Helvetica" text-anchor="middle" '
                   'fill="%s">%s</text></g>' % (clip, x + ww / 2, y + hh / 2 + 3.6 * SCALE, 10 * SCALE,
                                                rgb(w.get("fs") or [0.8, 0.8, 0.8]), esc(w["text"])))
    elif w["kind"] == "GameTooltip":
        svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#0b0b18" fill-opacity="0.9" stroke="#666" rx="3"/>'
                   % (x, y, ww, hh))
        svg.append('<text x="%.1f" y="%.1f" font-size="%.1f" font-family="Helvetica" fill="#ccc">(the rank\'s own tooltip)</text>'
                   % (x + 8, y + 14 * SCALE / 2 + 6, 10 * SCALE))
    elif w["kind"] == "EditBox":
        svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#000" fill-opacity="0.5" stroke="#777" '
                   'stroke-width="1" rx="2"/>' % (x, y, ww, hh))
    elif w["kind"] == "Frame" and "UIDropDownMenuTemplate" in (w["tmpl"] or ""):
        svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#000" fill-opacity="0.5" stroke="#777" '
                   'stroke-width="1" rx="2"/>' % (x + 16, y + 4, max(0, ww - 32), max(0, hh - 8)))

svg.append("</svg>")
open(dst, "w", encoding="utf-8").write("\n".join(svg))
print("wrote", dst)
