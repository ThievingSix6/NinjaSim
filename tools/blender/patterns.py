"""2D ornament painting (PIL) for the hero models' decals: greek keys, diamonds,
runes, knots, scrolls, stitches, emboss/engrave strokes.

A decal is an RGBA image laid over a part through its "Decal" UV layer (hero.py):
alpha is coverage, so untouched pixels keep the part's own colour.
Coordinates here are pixels of that image.
"""
import math
import random

from PIL import Image, ImageDraw, ImageFilter

DARK = (20, 20, 24)
LIGHT = (255, 255, 255)


class Decal:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    def layer(self):
        return Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))

    def put(self, layer, blur=0):
        if blur:
            layer = layer.filter(ImageFilter.GaussianBlur(blur))
        self.img = Image.alpha_composite(self.img, layer)

    def engrave(self, strokes, width=3, depth=150, light=110, offset=None, closed=False):
        """Incised lines: a dark groove with a light lip below-right (reads as cut metal)."""
        off = offset if offset is not None else max(1, width // 2 + 1)
        hi = self.layer()
        lo = self.layer()
        dh, dl = ImageDraw.Draw(hi), ImageDraw.Draw(lo)
        for pts in strokes:
            p = list(pts) + ([pts[0]] if closed else [])
            dh.line([(x + off, y + off) for x, y in p], fill=(*LIGHT, light), width=width, joint="curve")
            dl.line(p, fill=(*DARK, depth), width=width, joint="curve")
        self.put(hi, 0.6)
        self.put(lo, 0.6)

    def emboss(self, strokes, width=3, color=None, shade=120, light=120, closed=False):
        """Raised lines: light top-left edge, dark bottom-right shadow, optional fill colour."""
        a, b, c = self.layer(), self.layer(), self.layer()
        da, db, dc = ImageDraw.Draw(a), ImageDraw.Draw(b), ImageDraw.Draw(c)
        off = max(1, width // 2)
        for pts in strokes:
            p = list(pts) + ([pts[0]] if closed else [])
            db.line([(x + off, y + off) for x, y in p], fill=(*DARK, shade), width=width + 1, joint="curve")
            da.line([(x - off * 0.6, y - off * 0.6) for x, y in p], fill=(*LIGHT, light), width=width, joint="curve")
            if color:
                dc.line(p, fill=(*color, 255), width=max(1, width - 1), joint="curve")
        self.put(b, 0.8)
        self.put(a, 0.5)
        if color:
            self.put(c, 0.3)

    def glow(self, strokes, color, width=4, halo=10, closed=False):
        """Glowing inlay: bright core line with a soft coloured halo."""
        h, c = self.layer(), self.layer()
        dh, dc = ImageDraw.Draw(h), ImageDraw.Draw(c)
        for pts in strokes:
            p = list(pts) + ([pts[0]] if closed else [])
            dh.line(p, fill=(*color, 150), width=width + halo, joint="curve")
            dc.line(p, fill=(*color, 255), width=width, joint="curve")
            dc.line(p, fill=(*[min(255, v + 150) for v in color], 255), width=max(1, width // 3), joint="curve")
        self.put(h, halo * 0.45)
        self.put(c, 0.5)

    def fill(self, polys, color, alpha=255, blur=0.6):
        l = self.layer()
        d = ImageDraw.Draw(l)
        for p in polys:
            d.polygon(p, fill=(*color, alpha))
        self.put(l, blur)

    def save(self, path):
        self.img.save(path)
        return path


# ---------------------------------------------------------------- shapes (return lists of strokes)
def rect(x0, y0, x1, y1):
    return [[(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)]]


def diamond(cx, cy, rx, ry):
    return [[(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy), (cx, cy - ry)]]


def meander_unit(x, y, s, flip=False):
    """One greek-key spiral in an s x s cell (the classic squared hook)."""
    u = s / 5.0
    pts = [(0, 5), (0, 0), (5, 0), (5, 4), (2, 4), (2, 2), (3, 2)]
    if flip:
        pts = [(5 - a, b) for a, b in pts]
    return [[(x + a * u, y + b * u) for a, b in pts]]


def meander_band(x0, y0, length, s, vertical=False):
    """A running greek-key frieze of cells of size s."""
    out = []
    n = max(1, int(length // s))
    for i in range(n):
        if vertical:
            out += meander_unit(x0, y0 + i * s, s * 0.86, flip=i % 2 == 1)
        else:
            out += meander_unit(x0 + i * s, y0, s * 0.86, flip=False)
    return out


def meander_block(x0, y0, w, h):
    """Greek-key panel: border + two interlocking hooks (guard caps, pommel face)."""
    s = min(w, h)
    out = rect(x0, y0, x0 + w, y0 + h)
    m = s * 0.16
    iw, ih = w - 2 * m, h - 2 * m
    u = min(iw, ih) / 5
    hook = [(0, 5), (0, 0), (4, 0), (4, 3), (2, 3), (2, 2)]
    out.append([(x0 + m + a * u, y0 + m + b * u) for a, b in hook])
    out.append([(x0 + w - m - a * u, y0 + h - m - b * u) for a, b in hook])
    return out


def stepped_line(x, y0, y1, amp, step, rnd):
    """The pixel-stepped temper line on the green blade."""
    pts = [(x, y0)]
    y = y0
    cx = x
    while y < y1:
        y2 = min(y1, y + rnd.uniform(step * 0.6, step * 1.6))
        pts.append((cx, y2))
        cx = x + rnd.choice([-1, 0, 1, 1]) * amp * rnd.uniform(0.3, 1.0)
        pts.append((cx, y2))
        y = y2
    return [pts]


def rune(cx, cy, s, rnd):
    """A random angular glyph (2-4 strokes on a 3x4 grid)."""
    grid = [(i, j) for i in range(3) for j in range(4)]
    strokes = [[(1, 0), (1, 3)]] if rnd.random() < 0.7 else [[(0, 0), (0, 3)]]
    for _ in range(rnd.randint(1, 3)):
        a = rnd.choice(grid)
        b = rnd.choice([g for g in grid if g != a and abs(g[0] - a[0]) <= 2 and abs(g[1] - a[1]) <= 2])
        strokes.append([a, b])
    u = s / 3.0
    return [[(cx + (a - 1) * u, cy + (b - 1.5) * u) for a, b in st] for st in strokes]


def knot(cx, cy, r, n=3):
    """Interlaced square knot: a diamond lattice (a square grid turned 45 degrees)
    with a looped cord on each of its four corners."""
    out = []
    for i in range(n + 1):
        t = -r / 2 + i * r / n
        out.append([_rot45(t, -r / 2, cx, cy), _rot45(t, r / 2, cx, cy)])
        out.append([_rot45(-r / 2, t, cx, cy), _rot45(r / 2, t, cx, cy)])
    reach = r / math.sqrt(2)
    for a in range(4):
        ang = a * math.pi / 2
        ox, oy = cx + math.cos(ang) * reach, cy + math.sin(ang) * reach
        out.append(arc(ox, oy, r * 0.2, ang - math.pi * 0.8, ang + math.pi * 0.8))
    return out


def _rot45(x, y, cx, cy):
    c = math.sqrt(0.5)
    return (cx + (x - y) * c, cy + (x + y) * c)


def arc(cx, cy, r, a0, a1, n=16):
    return [(cx + math.cos(a0 + (a1 - a0) * i / n) * r, cy + math.sin(a0 + (a1 - a0) * i / n) * r) for i in range(n + 1)]


def spiral(cx, cy, r0, r1, turns, a0=0.0, n=60, cw=1):
    pts = []
    for i in range(n + 1):
        t = i / n
        a = a0 + cw * t * turns * 2 * math.pi
        r = r0 + (r1 - r0) * t
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def scroll_vine(x, y0, y1, amp, period, rnd=None):
    """Wavy stem with curled spiral leaves either side (filigree borders)."""
    out = []
    stem = [(x + math.sin((y - y0) / period * 2 * math.pi) * amp, y) for y in frange(y0, y1, 3)]
    out.append(stem)
    y = y0 + period * 0.25
    side = 1
    while y < y1 - period * 0.2:
        sx = x + math.sin((y - y0) / period * 2 * math.pi) * amp
        out.append(spiral(sx + side * amp * 1.4, y, amp * 1.3, amp * 0.2, 1.1, a0=math.pi if side > 0 else 0, cw=side))
        y += period / 2
        side = -side
    return out


def frange(a, b, s):
    out = []
    v = a
    while v <= b:
        out.append(v)
        v += s
    return out


def stitches(pts, length=10, gap=8, width=3):
    """Dashes along a polyline (hood seams, sleeve hems)."""
    out = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        d = math.hypot(x1 - x0, y1 - y0)
        if d == 0:
            continue
        ux, uy = (x1 - x0) / d, (y1 - y0) / d
        s = 0.0
        while s + length <= d:
            out.append([(x0 + ux * s, y0 + uy * s), (x0 + ux * (s + length), y0 + uy * (s + length))])
            s += length + gap
    return out


def rng(seed):
    return random.Random(seed)
