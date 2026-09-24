# Commander_Vault: the bank's stone, as a tile.
#
# The stock bank window is one 384x512 sheet -- border, title bar, sockets and
# stone all baked together -- so a resizable window cannot wear it. Cutting a
# tile out of its stone does not work either: that stone carries long diagonal
# scratches cut for a window shown ONCE, and repeated across a wide window they
# read as wallpaper, whichever way the tile is made seamless.
#
# So the MATERIAL is reproduced rather than the pixels: the palette, the
# spread and the grain are measured off the sheet's open stone
# (mean 106/99/93, sd ~15) and rebuilt as periodic value noise, which is
# seamless by construction at any size and has no motif to repeat. A handful
# of faint wrapped scratches put the character back.
import math, random
from png import write_png

SIZE = 256
random.seed(20250908)

def value_noise(period):
    g = [[random.random() for _ in range(period)] for _ in range(period)]
    def smooth(t):
        return t*t*(3 - 2*t)
    out = [[0.0]*SIZE for _ in range(SIZE)]
    step = SIZE / period
    for y in range(SIZE):
        fy = y / step
        y0 = int(fy) % period; y1 = (y0+1) % period
        ty = smooth(fy - int(fy))
        for x in range(SIZE):
            fx = x / step
            x0 = int(fx) % period; x1 = (x0+1) % period
            tx = smooth(fx - int(fx))
            a = g[y0][x0]*(1-tx) + g[y0][x1]*tx
            b = g[y1][x0]*(1-tx) + g[y1][x1]*tx
            out[y][x] = a*(1-ty) + b*ty
    return out

field = [[0.0]*SIZE for _ in range(SIZE)]
amp, total = 1.0, 0.0
for period in (4, 8, 16, 32, 64, 128, 256):
    n = value_noise(period)
    for y in range(SIZE):
        for x in range(SIZE):
            field[y][x] += n[y][x]*amp
    total += amp
    amp *= 0.62
for y in range(SIZE):
    for x in range(SIZE):
        field[y][x] /= total

# Faint scratches, wrapped so they cross the tile edge and continue
scratch = [[0.0]*SIZE for _ in range(SIZE)]
for _ in range(26):
    x = random.uniform(0, SIZE); y = random.uniform(0, SIZE)
    ang = random.uniform(0, math.pi*2)
    dx, dy = math.cos(ang), math.sin(ang)
    length = random.uniform(18, 70)
    depth = random.uniform(-0.30, -0.10) if random.random() < 0.65 else random.uniform(0.10, 0.24)
    for step in range(int(length)):
        fade = math.sin(math.pi * step / length)
        px, py = int(x) % SIZE, int(y) % SIZE
        scratch[py][px] += depth * fade
        if random.random() < 0.4:
            scratch[py][(px+1) % SIZE] += depth * fade * 0.5
        x += dx + random.uniform(-0.25, 0.25)
        y += dy + random.uniform(-0.25, 0.25)

# A one-pixel box blur takes the aliasing off the scratches without
# flattening them
soft = [[0.0]*SIZE for _ in range(SIZE)]
for y in range(SIZE):
    for x in range(SIZE):
        s = 0.0
        for j in (-1, 0, 1):
            for i in (-1, 0, 1):
                s += scratch[(y+j) % SIZE][(x+i) % SIZE]
        soft[y][x] = s/9.0

# Measured off the stock sheet's open stone
MEAN = (106.0, 99.0, 93.0)
SPREAD = 54.0
# Fine tooth. Value noise alone comes out soft, and stone that is soft at the
# pixel level reads as fog rather than rock.
GRAIN = 7.0
grain = [[random.uniform(-1.0, 1.0) for _ in range(SIZE)] for _ in range(SIZE)]
out = bytearray(SIZE*SIZE*4)
for y in range(SIZE):
    for x in range(SIZE):
        v = (field[y][x] - 0.5) * SPREAD + soft[y][x] * 58.0 + grain[y][x] * GRAIN
        i = (y*SIZE + x)*4
        for c in range(3):
            # Warmer where the stone is lighter, the way weathered rock reads
            val = MEAN[c] + v * (1.0 + (0.06 if c == 0 else (0.0 if c == 1 else -0.06)))
            out[i+c] = 0 if val < 0 else (255 if val > 255 else int(val+0.5))
        out[i+3] = 255

write_png('BankStone.png', SIZE, SIZE, out)
n = SIZE*SIZE
print('mean', [round(sum(out[i*4+c] for i in range(n))/n, 1) for c in range(3)],
      'range', [(min(out[i*4+c] for i in range(n)), max(out[i*4+c] for i in range(n))) for c in range(3)])
