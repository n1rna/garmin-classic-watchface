#!/usr/bin/env python3
"""Generate the anti-aliased icon font (BMFont text format + PNG atlas).

Glyphs (drawn white; tinted on the watch with dc.setColor):
  A heart   B steps   C sun   D partly cloudy   E cloud
  F rain    G thunder H snow  I fog

Usage: python3 tools/gen_icons.py      (run from the project root)
"""
import math, os, struct, zlib

GLYPHS = "ABCDEFGHI"
# resource folder -> glyph pixel size
# resource folder -> (regular glyph size, small glyph size for the windows)
TARGETS = {
    "resources/fonts": (24, 16),
    "resources-round-240x240/fonts": (18, 12),
    "resources-round-260x260/fonts": (18, 13),
    "resources-round-280x280/fonts": (20, 14),
    "resources-round-360x360/fonts": (24, 16),
    "resources-round-390x390/fonts": (26, 17),
    "resources-round-416x416/fonts": (28, 18),
    "resources-round-454x454/fonts": (30, 20),
}

# ---- signed distance primitives (unit box, y down) -------------------------
def circle(x, y, cx, cy, r):
    return math.hypot(x - cx, y - cy) - r

def capsule(x, y, ax, ay, bx, by, r):
    px, py, dx, dy = x - ax, y - ay, bx - ax, by - ay
    h = max(0.0, min(1.0, (px * dx + py * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - dx * h, py - dy * h) - r

def rbox(x, y, cx, cy, hw, hh, rad):
    qx = abs(x - cx) - hw + rad
    qy = abs(y - cy) - hh + rad
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - rad

def ellipse(x, y, cx, cy, a, b, ang=0.0):
    c, s = math.cos(ang), math.sin(ang)
    dx, dy = x - cx, y - cy
    lx, ly = dx * c + dy * s, -dx * s + dy * c
    return (math.hypot(lx / a, ly / b) - 1) * min(a, b)

def polygon(x, y, pts):
    d = float("inf"); inside = False
    for i in range(len(pts)):
        ax, ay = pts[i - 1]; bx, by = pts[i]
        d = min(d, capsule(x, y, ax, ay, bx, by, 0))
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            inside = not inside
    return -d if inside else d

def heart_sdf(px, py):  # Inigo Quilez heart, y up, tip at origin
    px = abs(px)
    if py + px > 1.0:
        return math.hypot(px - 0.25, py - 0.75) - math.sqrt(2) / 4
    m = 0.5 * max(px + py, 0.0)
    d = min((px) ** 2 + (py - 1) ** 2, (px - m) ** 2 + (py - m) ** 2)
    return math.sqrt(d) * (1 if px > py else -1)

U = min
def SUB(a, b): return max(a, -b)

def cloud(x, y, cx, cy, s):
    return U(circle(x, y, cx - .22 * s, cy + .06 * s, .20 * s),
             circle(x, y, cx + .02 * s, cy - .08 * s, .27 * s),
             circle(x, y, cx + .25 * s, cy + .07 * s, .19 * s),
             rbox(x, y, cx + .015 * s, cy + .14 * s, .42 * s, .12 * s, .12 * s))

def sun(x, y, cx, cy, core, r1, r2, w):
    d = circle(x, y, cx, cy, core)
    for i in range(8):
        a = i * math.pi / 4
        d = U(d, capsule(x, y, cx + math.sin(a) * r1, cy - math.cos(a) * r1,
                         cx + math.sin(a) * r2, cy - math.cos(a) * r2, w))
    return d

def flake(x, y, cx, cy, l, w):
    d = float("inf")
    for i in range(3):
        a = i * math.pi / 3
        d = U(d, capsule(x, y, cx - math.cos(a) * l, cy - math.sin(a) * l,
                         cx + math.cos(a) * l, cy + math.sin(a) * l, w))
    return d

GAP = 0.055
BOLT = [(.58, .46), (.36, .74), (.50, .74), (.42, .97), (.68, .64), (.54, .64), (.64, .46)]

def glyph(ch, x, y):
    if ch == "A":
        S = 0.70
        return heart_sdf((x - .5) / S, (.88 - y) / S) * S
    if ch == "B":
        def foot(fx, fy, ang):
            c, s = math.cos(ang), math.sin(ang)
            hx, hy = fx - s * .27, fy + c * .27
            return U(ellipse(x, y, fx, fy, .12, .18, ang), circle(x, y, hx + 0, hy + .02, .085))
        return U(foot(.30, .38, -.16), foot(.70, .25, .16))
    if ch == "C":
        return sun(x, y, .5, .5, .20, .31, .43, .045)
    if ch == "D":
        cl = cloud(x, y, .58, .62, .80)
        return U(SUB(sun(x, y, .37, .37, .15, .23, .32, .038), cl - GAP), cl)
    if ch == "E":
        return cloud(x, y, .5, .55, 1.05)
    if ch == "F":
        cl = cloud(x, y, .5, .42, .95)
        d = cl
        for dx in (.30, .50, .70):
            d = U(d, capsule(x, y, dx + .03, .76, dx - .04, .92, .035))
        return d
    if ch == "G":
        cl = cloud(x, y, .5, .40, .95)
        b = polygon(x, y, BOLT)
        return U(SUB(cl, b - GAP), b)
    if ch == "H":
        cl = cloud(x, y, .5, .40, .95)
        return U(cl, circle(x, y, .30, .80, .055), circle(x, y, .70, .80, .055),
                 circle(x, y, .50, .91, .055))
    if ch == "I":
        cl = cloud(x, y, .5, .37, .92)
        return U(cl, capsule(x, y, .16, .74, .84, .74, .036), capsule(x, y, .28, .88, .72, .88, .036))
    raise ValueError(ch)

# ---- rasterise --------------------------------------------------------------
def render(ch, n):
    ss = 3
    px = []
    for j in range(n):
        row = []
        for i in range(n):
            cov = 0.0
            for sj in range(ss):
                for si in range(ss):
                    x = (i + (si + .5) / ss) / n
                    y = (j + (sj + .5) / ss) / n
                    d = glyph(ch, x, y) * n * ss
                    cov += max(0.0, min(1.0, 0.5 - d))
            row.append(int(round(255 * cov / (ss * ss))))
        px.append(row)
    return px

def write_png(path, w, h, alpha_rows):
    raw = b"".join(b"\x00" + b"".join(bytes((255, 255, 255, a)) for a in r) for r in alpha_rows)
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

def build(folder, n, name="icons"):
    os.makedirs(folder, exist_ok=True)
    pad = 2
    W, H = len(GLYPHS) * (n + pad), n
    atlas = [[0] * W for _ in range(H)]
    chars = []
    for k, ch in enumerate(GLYPHS):
        g = render(ch, n)
        ox = k * (n + pad)
        for j in range(n):
            atlas[j][ox:ox + n] = g[j]
        chars.append(f"char id={ord(ch)} x={ox} y=0 width={n} height={n} xoffset=0 yoffset=0 "
                     f"xadvance={n} page=0 chnl=15")
    write_png(os.path.join(folder, name + ".png"), W, H, atlas)
    with open(os.path.join(folder, name + ".fnt"), "w") as f:
        f.write(f'info face="Icons" size={n} bold=0 italic=0 charset="" unicode=1 stretchH=100 '
                f'smooth=1 aa=1 padding=0,0,0,0 spacing={pad},0 outline=0\n'
                f"common lineHeight={n} base={n} scaleW={W} scaleH={H} pages=1 packed=0\n"
                f'page id=0 file="{name}.png"\nchars count={len(chars)}\n' + "\n".join(chars) + "\n")

if __name__ == "__main__":
    for folder, (n, ns) in TARGETS.items():
        build(folder, n, "icons")
        build(folder, ns, "icons_small")
        with open(os.path.join(folder, "fonts.xml"), "w") as f:
            f.write("<fonts>\n"
                    f'    <font id="Icons" filename="icons.fnt" antialias="true" filter="{GLYPHS}"/>\n'
                    f'    <font id="IconsSmall" filename="icons_small.fnt" antialias="true" filter="{GLYPHS}"/>\n'
                    "</fonts>\n")
        print(f"{folder}: {n}px / {ns}px")
    build("preview", 96)  # large atlas for the browser preview
