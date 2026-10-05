#!/usr/bin/env python3
"""Generate the radial plate's clock-wipe art: two half discs.

HalfRight.png is the right half of a disc (twelve round to six, clockwise),
HalfLeft.png the left half. The disc's radius is WIPE_RADIUS of the width,
so a fully transparent margin surrounds it: a texture rotated by Texture:
SetRotation samples past its own edge at the corners, and clamping a
transparent margin smears nothing. The addon mirrors WIPE_RADIUS
(CommanderPlatesRadial.lua) to size the quads so the disc lands exactly on
the face.

    python3 Harness/make_wipe.py
"""
import os
import struct
import zlib

SIZE = 128
SS = 4
WIPE_RADIUS = 0.46


def write_png(path, pixels):
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)
        raw.extend(pixels[y * SIZE * 4:(y + 1) * SIZE * 4])

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def half(right):
    center, radius = SIZE / 2.0, SIZE * WIPE_RADIUS
    pixels = bytearray(SIZE * SIZE * 4)
    step = 1.0 / SS
    for py in range(SIZE):
        for px in range(SIZE):
            total = 0
            for sy in range(SS):
                for sx in range(SS):
                    x = px + step / 2 + sx * step - center
                    y = py + step / 2 + sy * step - center
                    inside = x * x + y * y <= radius * radius
                    side = x >= 0 if right else x < 0
                    if inside and side:
                        total += 1
            a = int(round(255 * total / (SS * SS)))
            o = (py * SIZE + px) * 4
            pixels[o:o + 4] = bytes((255, 255, 255, a))
    return pixels


def main():
    target = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Textures")
    write_png(os.path.join(target, "HalfRight.png"), half(True))
    write_png(os.path.join(target, "HalfLeft.png"), half(False))


if __name__ == "__main__":
    main()
