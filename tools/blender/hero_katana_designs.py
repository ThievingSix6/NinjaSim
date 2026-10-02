"""Hero katana designs for every sword after the first three (see hero_katanas.py).

One builder per Katanas.lua id. Each returns (parts, glow, sharp) like the original
three and records the blade base/tip in hero_katana_kit.INFO. The Look colours in
src/shared/Config/Katanas.lua are the brief; rarity drives ornament and glow:
  Uncommon  engraved, no neon
  Rare      neon gems + inlays
  Epic      + neon edge
  Legendary + bigger guards, crystals, more inlays
  Mythic    + cracks / veins / teeth, glow everywhere
  Divine    + floating pieces, the biggest guards
"""
import math

import hero_katana_kit as K
import patterns as P
from hero_katana_kit import GOLD, SILVER, Blade, Sword, mix, sym

DECALS = "/tmp"


def setup(decal_dir):
    global DECALS
    DECALS = decal_dir


def ellipse_arc(cz, cdy, rz, rdy, a0, a1, n=12):
    return [(cz + math.cos(a0 + (a1 - a0) * i / n) * rz, cdy + math.sin(a0 + (a1 - a0) * i / n) * rdy) for i in range(n + 1)]


def inset(outline, k, dz=0.0, ddy=0.0):
    cz = sum(p[0] for p in outline) / len(outline)
    cd = sum(p[1] for p in outline) / len(outline)
    return [(cz + (z - cz) * k + dz, cd + (d - cd) * k + ddy) for z, d in outline]



def leaf(bz, bdy, angle, length, width, n=8, notch=0.0):
    """Pointed leaf / feather / petal outline [(z, dy)] from (bz, bdy) pointing at `angle`
    (radians from +Z toward +dy)."""
    ca, sa = math.cos(angle), math.sin(angle)
    top, bot = [], []
    for i in range(n + 1):
        t = i / n
        hw = width / 2 * math.sin(math.pi * min(1.0, t * 1.08)) ** 0.75 if t < 1 else 0.0
        if notch and 0 < i < n and i % 2 == 0:
            hw *= 1 - notch
        top.append((length * t, hw))
        bot.append((length * t, -hw))
    pts = top + list(reversed(bot[1:-1]))
    return [(bz + x * ca - y * sa, bdy + x * sa + y * ca) for x, y in pts]


def mirror(outline):
    return [(-z, dy) for z, dy in reversed(outline)]


def star_out(r_out, r_in, n, rot=math.pi / 2, sq=1.0):
    return [(math.cos(rot + k * math.pi / n) * (r_out if k % 2 == 0 else r_in), math.sin(rot + k * math.pi / n) * (r_out if k % 2 == 0 else r_in) * sq)
            for k in range(2 * n)]


def circ_out(r, n=24, sq=1.0, fn=None):
    out = []
    for k in range(n):
        a = 2 * math.pi * k / n
        rr = fn(a) if fn else r
        out.append((math.cos(a) * rr, math.sin(a) * rr * sq))
    return out


def outline_paint(outline, k=0.82, color=GOLD, width=6, fill=None, spirals=(), lines=(), engrave_k=None):
    """Plate painter: optional enamel fill + embossed inset border (+ engraved extras)."""
    def paint(d, gx, gy):
        ins = [(gx(z), gy(dy)) for z, dy in inset(outline, k)]
        if fill:
            d.fill([ins], fill)
        d.emboss([ins], width=width, color=color, closed=True)
        if engrave_k:
            d.engrave([[(gx(z), gy(dy)) for z, dy in inset(outline, engrave_k)]], width=3, depth=150, closed=True)
        for (z, dy, r, cw) in spirals:
            d.engrave([P.spiral(gx(z), gy(dy), r, 2, 1.3, cw=cw)], width=3, depth=150)
        for st in lines:
            d.engrave([[(gx(z), gy(dy)) for z, dy in st]], width=3, depth=150)
    return paint


def feather_paint(outline, bz, bdy, angle, length, color=GOLD, fill=None):
    """Feather: border + quill line + barbs."""
    ca, sa = math.cos(angle), math.sin(angle)

    def P2(x, y):
        return (bz + x * ca - y * sa, bdy + x * sa + y * ca)

    def paint(d, gx, gy):
        ins = [(gx(z), gy(dy)) for z, dy in inset(outline, 0.8)]
        if fill:
            d.fill([ins], fill)
        d.emboss([ins], width=7, color=color, closed=True)
        q = [P2(length * 0.06, 0), P2(length * 0.78, 0)]
        d.emboss([[(gx(z), gy(dy)) for z, dy in q]], width=6, color=color)
    return paint


def wings(sw, yc, feathers, rgb, trim=GOLD, fill=None, thick=0.2, glow_tips=False):
    """Feathered wings: `feathers` = [(bz, bdy, angle_deg, length, width)] for the +Z wing;
    the -Z wing mirrors it. Inner feathers are thicker so the layers read."""
    for side in (1, -1):
        for i, (bz, bdy, ang, ln, wd) in enumerate(feathers):
            a = math.radians(ang)
            out = leaf(bz, bdy, a, ln, wd)
            if side < 0:
                out = mirror(out)
                a2 = math.pi - a
                pz = -bz
            else:
                a2, pz = a, bz
            sw.plate(out, yc, thick * (1 - 0.12 * i), rgb, bevel=0.016, paint=feather_paint(out, pz, bdy, a2, ln, trim, fill))
            if glow_tips:
                tz, tdy = pz + math.cos(a2) * ln * 0.8, bdy + math.sin(a2) * ln * 0.8
                sw.gem((0, yc + tdy, tz), 0.035, thick * (1 - 0.12 * i) / 2 + 0.01, 4)

def crescent(span, top, bottom, mid, n=14, up=True):
    """Crescent outline [(z, dy)]: horns at (+-span, top), belly down to `bottom`,
    inner arc down to `mid` (up=False flips it so the horns point to the grip)."""
    outer = [(span * math.cos(math.pi + math.pi * i / n), top + (bottom - top) * math.sin(math.pi * i / n)) for i in range(n + 1)]
    inner = [(span * math.cos(math.pi * i / n) * 0.999, top + (mid - top) * math.sin(math.pi * i / n)) for i in range(1, n)]
    pts = outer + inner
    if not up:
        pts = [(z, -d) for z, d in reversed(pts)]
    return pts


def paint_filigree(rgb_line=GOLD, width=6, k=0.82, spirals=(), engr=()):
    """Plate painter: embossed (gold) inset border, engraved spirals at (z, dy) points."""
    def fn(outline):
        def paint(d, gx, gy):
            ins = inset(outline, k)
            d.emboss([[(gx(z), gy(dy)) for z, dy in ins]], width=width, color=rgb_line, closed=True)
            for (z, dy, r, cw) in spirals:
                d.engrave([P.spiral(gx(z), gy(dy), r, 3, 1.3, cw=cw)], width=3, depth=150)
            for stroke in engr:
                d.engrave([[(gx(z), gy(dy)) for z, dy in stroke]], width=4, depth=160)
        return paint
    return fn


def engraved_block(border=True, spirals=4, key=False, color=None, rings=0):
    def paint(d, w, h):
        if border:
            d.engrave(P.rect(6, 6, w - 6, h - 6), width=4, depth=150)
        if key:
            d.engrave(P.meander_band(12, h / 2 - 12, w - 24, 24), width=3, depth=160)
        if spirals == 4:
            r = min(w, h) * 0.12
            for (fx, fy, cw) in ((0.27, 0.32, 1), (0.73, 0.32, -1), (0.27, 0.68, -1), (0.73, 0.68, 1)):
                d.engrave([P.spiral(w * fx, h * fy, r, 2, 1.3, cw=cw)], width=3, depth=160)
        elif spirals == 2:
            r = min(w, h) * 0.2
            for side in (-1, 1):
                d.engrave([P.spiral(w / 2 + side * w * 0.22, h / 2, r, 2, 1.3, cw=side)], width=3, depth=160)
        for i in range(rings):
            m = 10 + i * 8
            d.emboss(P.rect(m, m, w - m, h - m), width=3, color=color)
    return paint


def blade_runes(bl, rnd, ya, yb, f, n, size, glow_rgb, inlay=True, paint=True, width=0.024):
    strokes = []
    for i in range(n):
        y = ya + (yb - ya) * (i + 0.5) / n
        st = K.rune_strokes(y, bl.flat(y, f), size, rnd)
        strokes += st
        if paint:
            bl.decal.glow([bl.pline(s) for s in st], glow_rgb, width=5, halo=9)
    if inlay:
        bl.inlay(strokes, width=width)
    return strokes


def channel(bl, ya, yb, fa, fb, rgb, border=True, depth=200):
    poly = bl.band_poly(ya, yb, fa, fb)
    bl.decal.fill([poly], rgb, blur=1)
    if border:
        bl.decal.engrave([poly + [poly[0]]], width=4, depth=depth)


# ====================================================================== tier swords
def amethyst_katana():
    glow = (210, 140, 255)
    sw = Sword("amethyst_katana", glow, DECALS)
    rnd = P.rng(41)
    purple, dark = (112, 52, 176), (52, 20, 92)
    y0, L, w = 1.02, 3.9, 0.5
    edge, spine = K.katana_outline(y0, L, w, clip=0.55, wf=lambda s: 1 + 0.12 * s)
    bl = Blade(sw, edge, spine, thick=0.11, bevel=0.12, kissaki=y0 + L - 0.75, bend=lambda s: 0.45 * s * s)
    d = bl.decal
    bl.paint_bevel((232, 222, 252))
    ya, yb = y0 + 0.12, y0 + L - 0.95
    channel(bl, ya, yb, 0.3, 0.9, (98, 60, 150))
    # crystal lattice in the channel: engraved diamonds, glowing amethyst facets
    gems = []
    for i in range(6):
        y = ya + 0.28 + i * (yb - ya - 0.5) / 5
        zc = bl.flat(y, 0.6)
        d.engrave([bl.pline(K.diamond_poly(y, zc, 0.2, 0.1) + [K.diamond_poly(y, zc, 0.2, 0.1)[0]])], width=3, depth=200)
        if i % 2 == 0:
            gems.append(K.diamond_poly(y, zc, 0.13, 0.065))
            d.glow([bl.pline(gems[-1] + [gems[-1][0]])], glow, width=5, halo=10)
        else:
            d.glow([bl.pline([(y - 0.12, zc), (y + 0.12, zc)])], glow, width=4, halo=8)
            bl.inlay([[(y - 0.1, zc), (y + 0.1, zc)]], width=0.022)
    bl.slab(gems)
    d.engrave([bl.pline(bl.line(0.97, y0 + 0.1, y0 + L - 0.9))], width=3, depth=150)
    for i in range(5):
        y = y0 + 0.3 + i * 0.5
        d.glow([bl.pline(s) for s in K.rune_strokes(y, bl.flat(y, 0.13), 0.09, rnd)], glow, width=4, halo=7)
    bl.finish((214, 204, 238))

    # crescent guard with silver filigree, crystal clusters on the horns, hex gem
    yc = 0.86
    cres = crescent(0.78, 0.42, -0.24, 0.08)
    mid = [(0.7 * math.cos(math.pi + math.pi * i / 12), 0.4 - 0.48 * math.sin(math.pi * i / 12)) for i in range(13)]
    sw.plate(cres, yc, 0.24, purple, bevel=0.02, paint=lambda dd, gx, gy: (
        dd.emboss([[(gx(z), gy(dy)) for z, dy in mid]], width=7, color=SILVER),
        dd.engrave([P.spiral(gx(s * 0.5), gy(-0.04), 14, 3, 1.3, cw=s) for s in (-1, 1)], width=3, depth=150)))
    for side in (-1, 1):
        hz = side * 0.74
        sw.crystal((0, yc + 0.36, hz), (0, 1, side * 0.5), 0.36, 0.07)
        sw.crystal((0, yc + 0.34, hz - side * 0.07), (0, 1, side * 1.6), 0.24, 0.05)
        sw.crystal((0, yc + 0.38, hz - side * 0.12), (0, 1, -side * 0.2), 0.2, 0.045)
        sw.crystal((0, yc - 0.18, side * 0.3), (0, -1, side * 0.6), 0.14, 0.04)
        sw.stud((0, yc + 0.0, side * 0.46), 0.04, 0.14, SILVER)
    octo = [(math.cos(math.pi / 8 + k * math.pi / 4) * 0.24, math.sin(math.pi / 8 + k * math.pi / 4) * 0.24) for k in range(8)]
    sw.plate(octo, yc + 0.02, 0.34, dark, bevel=0.025, paint=outline_paint(octo, 0.8, color=SILVER, width=5))
    sw.setting((0, yc + 0.02, 0), 0.15, 0.17, SILVER)
    sw.gem((0, yc + 0.02, 0), 0.13, 0.2, 6)
    sw.box((0.2, 0.24, 0.6), (0, yc + 0.27, 0.0), SILVER, bevel=0.02, paint=engraved_block(spirals=2), roughness=0.3)

    # grip: dark violet core, lavender diamond straps, silver bands
    sw.grip(-0.62, 0.62, 0.14, 0.18, (40, 14, 70), (196, 150, 250), style="straps", width=0.18)
    sw.box((0.34, 0.12, 0.42), (0, 0.63, 0), SILVER, bevel=0.02, paint=engraved_block(spirals=2), roughness=0.3)
    # pommel: silver-trimmed purple block, gem, a crystal spike hanging below
    sw.box((0.34, 0.3, 0.44), (0, -0.78, 0), purple, bevel=0.035, paint=engraved_block(rings=1, color=SILVER, spirals=0))
    sw.setting((0, -0.78, 0), 0.11, 0.18, SILVER)
    sw.gem((0, -0.78, 0), 0.09, 0.2, 6)
    sw.crystal((0, -0.92, 0), (0, -1, 0), 0.26, 0.08)
    sw.claws(-0.97, 0.13, SILVER, drop=0.16)
    return sw.done()


def ember_katana():
    glow = (255, 80, 30)
    sw = Sword("ember_katana", glow, DECALS)
    rnd = P.rng(52)
    gold = (255, 184, 40)
    y0, L, w = 1.04, 4.0, 0.52
    edge, spine = K.katana_outline(y0, L, w, clip=0.6, wf=lambda s: 1 + 0.1 * s,
                                   edge_pts=K.waves(0.08, 0.82, 5, 0.03),
                                   spine_pts=K.teeth(0.55, 0.85, 3, 0.07, lean=0.75))
    bl = Blade(sw, edge, spine, thick=0.11, bevel=0.13, kissaki=y0 + L - 0.8, bend=lambda s: 0.55 * s * s)
    d = bl.decal
    # hot steel: orange bevel fading into the red flat, dark flame channel
    bl.paint_bevel((255, 150, 40))
    bl.paint_bevel((255, 214, 120), inset=0.55)
    channel(bl, y0 + 0.1, y0 + L - 1.0, 0.25, 0.85, (120, 24, 14))
    flames = []
    for i in range(4):
        y = y0 + 0.45 + i * 0.68
        zc = bl.flat(y, 0.55)
        fp = K.flame_poly(y, zc, 0.38, 0.13, lean=0.04)
        flames.append(K.flame_poly(y, zc, 0.3, 0.085, lean=0.04))
        d.fill([bl.pline(fp)], (255, 120, 40), blur=1)
        d.glow([bl.pline(flames[-1] + [flames[-1][0]])], (255, 190, 80), width=4, halo=10)
        for side in (-1, 1):
            d.engrave([P.spiral(*bl.px(y - 0.18, zc + side * 0.07), 9, 2, 1.2, cw=side)], width=3, depth=180)
    bl.slab(flames)
    for i in range(6):
        y = y0 + 0.25 + i * 0.5
        d.engrave([bl.pline(s) for s in K.rune_strokes(y, bl.flat(y, 0.94), 0.06, rnd)], width=3, depth=170)
    bl.edge_glow(y0 + 0.15, y0 + L - 0.02)
    bl.finish((200, 56, 34), roughness=0.3)

    # spiked sun-flame guard in gold, red enamel, big ember gem
    yc = 0.9
    half = [(0, 0.2), (0.1, 0.22), (0.2, 0.5), (0.27, 0.2), (0.42, 0.42), (0.44, 0.12), (0.7, 0.2),
            (0.5, -0.02), (0.6, -0.28), (0.36, -0.12), (0.18, -0.2), (0, -0.18)]
    out = sym(half)
    sw.plate(out, yc, 0.26, gold, bevel=0.018, roughness=0.3, paint=lambda dd, gx, gy: (
        dd.fill([[(gx(z), gy(dy)) for z, dy in inset(out, 0.7, ddy=0.01)]], (180, 30, 20)),
        dd.emboss([[(gx(z), gy(dy)) for z, dy in inset(out, 0.7, ddy=0.01)]], width=5, color=(255, 214, 110), closed=True),
        dd.engrave([P.spiral(gx(s * 0.3), gy(0.02), 12, 2, 1.2, cw=s) for s in (-1, 1)], width=3, depth=140)))
    for side in (-1, 1):
        sw.gem((0, yc + 0.02, side * 0.3), 0.06, 0.15, 4)
        for (z, dy) in ((0.2, 0.5), (0.42, 0.42), (0.7, 0.2), (0.6, -0.28)):
            sw.crystal((0, yc + dy - (0.08 if dy > 0 else -0.08), side * z * 0.9), (0, 1 if dy > 0 else -1, side * 0.6), 0.14, 0.03, sides=4)
    sw.ring(yc + 0.02, 0.12, 0.2, 0.34, gold, seg=16, roughness=0.3)
    sw.gem((0, yc + 0.02, 0), 0.12, 0.2, 8)
    sw.box((0.22, 0.24, 0.62), (0, yc + 0.3, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))

    # grip: dark red core, gold ribbon, gold bands
    sw.grip(-0.6, 0.66, 0.13, 0.17, (66, 12, 12), gold, style="straps", width=0.16)
    for y in (0.66, 0.02):
        sw.box((0.34, 0.12, 0.42), (0, y, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    # pommel: gold cap with spikes, tassel
    sw.box((0.36, 0.24, 0.46), (0, -0.74, 0), gold, bevel=0.035, roughness=0.3, paint=engraved_block(spirals=4))
    for side in (-1, 1):
        sw.spike((0, -0.74, side * 0.22), (0, -0.4, side), 0.16, 0.06, gold)
    sw.tassel((0, -0.86, 0), (255, 80, 30), length=0.62, lean=-0.2, cord_rgb=gold)
    return sw.done()


def gl(bl, strokes, rgb, width=5, halo=9):
    bl.decal.glow([bl.pline(st) for st in strokes], rgb, width=width, halo=halo)


def snowflake(cy, cz, r):
    out = []
    for k in range(3):
        a = math.pi / 2 + k * math.pi / 3
        dy, dz = math.sin(a) * r, math.cos(a) * r
        out.append([(cy - dy, cz - dz), (cy + dy, cz + dz)])
        for sgn in (-1, 1):
            by, bz = cy + sgn * dy * 0.55, cz + sgn * dz * 0.55
            for t in (-0.6, 0.6):
                b = a + t
                out.append([(by, bz), (by + sgn * math.sin(b) * r * 0.35, bz + sgn * math.cos(b) * r * 0.35)])
    return out


def bolt_poly(bl, ya, yb, fa, fb, n, thick):
    """Thick lightning bolt polygon (blade coords) zigzagging across the flat."""
    cl = []
    for i in range(n + 1):
        y = ya + (yb - ya) * i / n
        cl.append((y, bl.flat(y, fa if i % 2 == 0 else fb)))
    left = [(y, z + thick / 2) for y, z in cl]
    right = [(y, z - thick / 2) for y, z in reversed(cl)]
    tipy = yb + 0.12
    return left + [(tipy, cl[-1][1])] + right + [(ya - 0.1, cl[0][1])]


def sinuous(bl, ya, yb, fc, amp, waves, phase=0.0, n=60):
    return [(y, bl.flat(y, fc + amp * math.sin(phase + (y - ya) / (yb - ya) * waves * 2 * math.pi))) for y in bl.ys_between(ya, yb, n)]


def obsidian_katana():
    glow = (255, 40, 40)
    sw = Sword("obsidian_katana", glow, DECALS)
    rnd = P.rng(63)
    y0, L, w = 1.04, 4.1, 0.5
    edge, spine = K.katana_outline(y0, L, w, clip=0.5, tip="tanto", wf=lambda s: 1 + 0.06 * s,
                                   spine_pts=K.teeth(0.32, 0.84, 6, 0.05, lean=0.5, jitter=0.6, rnd=rnd))
    bl = Blade(sw, edge, spine, thick=0.12, bevel=0.13, kissaki=y0 + L - 0.62, bend=lambda s: 0.45 * s * s)
    d = bl.decal
    bl.paint_bevel((206, 210, 226))
    bl.paint_bevel((246, 246, 255), inset=0.6)
    # fracture facets: light hairlines over the black glass, glowing red fissures
    for i in range(14):
        y = y0 + 0.2 + rnd.uniform(0, L - 1.0)
        z = bl.flat(y, rnd.uniform(0.1, 0.9))
        a = rnd.uniform(0, math.pi)
        ln = rnd.uniform(0.08, 0.2)
        d.engrave([bl.pline([(y, z), (y + math.sin(a) * ln, z + math.cos(a) * ln * 0.5)])], width=2, depth=60, light=110)
    cracks = []
    for (ya, yb, f) in ((y0 + 0.15, y0 + 1.6, 0.5), (y0 + 1.5, y0 + 2.7, 0.45), (y0 + 2.6, y0 + 3.4, 0.5)):
        cracks += K.crack(rnd, ya, yb, lambda y, f=f: bl.flat(y, f), 0.05, n=8, branches=3, blen=0.35)
    d.glow([bl.pline(c) for c in cracks], (255, 60, 50), width=6, halo=12)
    bl.inlay(cracks, width=0.026)
    bl.finish((40, 40, 50), roughness=0.2)

    # layered square guard: silver frame, obsidian core, corner shards, red gem
    yc = 0.9
    sq = [(0.36, 0.25), (0.36, -0.2), (-0.36, -0.2), (-0.36, 0.25)]
    sw.plate(sq, yc, 0.24, (164, 170, 186), bevel=0.03, paint=outline_paint(sq, 0.84, color=(230, 232, 240), width=5, engrave_k=0.7))
    sw.plate(inset(sq, 0.62), yc, 0.32, (30, 30, 38), bevel=0.025, paint=outline_paint(inset(sq, 0.62), 0.8, color=(200, 30, 30), width=4))
    for sz, sdy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        sw.crystal((0, yc + 0.025 + sdy * 0.2, sz * 0.33), (0, sdy * 0.8, sz), 0.24, 0.06, rgb=(26, 26, 34), sides=4, glow=False)
        sw.stud((0, yc + 0.025 + sdy * 0.13, sz * 0.26), 0.035, 0.13, (230, 232, 240))
    sw.setting((0, yc + 0.02, 0), 0.12, 0.17, (220, 224, 236))
    sw.gem((0, yc + 0.02, 0), 0.1, 0.2, 4, roll=0.0)
    sw.box((0.22, 0.2, 0.56), (0, yc + 0.3, 0), (180, 184, 198), bevel=0.02, roughness=0.3, paint=engraved_block(spirals=0, key=True))
    sw.grip(-0.62, 0.66, 0.13, 0.17, (18, 18, 22), (200, 30, 30), style="straps", width=0.17)
    sw.box((0.34, 0.12, 0.42), (0, 0.66, 0), (180, 184, 198), bevel=0.02, roughness=0.3, paint=engraved_block(spirals=0, key=True))
    # pommel: silver block, red gem, a black glass shard below
    sw.box((0.36, 0.28, 0.46), (0, -0.77, 0), (164, 170, 186), bevel=0.035, roughness=0.3, paint=engraved_block(spirals=4))
    sw.gem((0, -0.77, 0), 0.08, 0.2, 4, roll=0.0)
    sw.crystal((0, -0.9, 0), (0, -1, 0), 0.32, 0.1, rgb=(26, 26, 34), sides=5, glow=False)
    for side in (-1, 1):
        sw.crystal((0, -0.88, side * 0.14), (0, -1, side * 0.8), 0.2, 0.06, rgb=(26, 26, 34), sides=4, glow=False)
    return sw.done()


def frostmoon_katana():
    glow = (160, 240, 255)
    sw = Sword("frostmoon_katana", glow, DECALS)
    rnd = P.rng(74)
    white, ice, navy = (232, 242, 255), (110, 180, 236), (40, 60, 100)
    y0, L, w = 1.06, 4.2, 0.54
    edge, spine = K.katana_outline(y0, L, w, clip=0.62, tip="hook", hook=0.07, wf=lambda s: 1 + 0.1 * s,
                                   spine_pts=K.teeth(0.03, 0.2, 3, 0.07, lean=0.8))
    bl = Blade(sw, edge, spine, thick=0.11, bevel=0.13, kissaki=y0 + L - 0.82, bend=lambda s: 0.5 * s * s)
    d = bl.decal
    bl.paint_bevel((246, 252, 255))
    ya, yb = y0 + 0.12, y0 + L - 0.98
    channel(bl, ya, yb, 0.28, 0.9, (150, 196, 236))
    # frost crystals creeping up from the edge
    for i in range(16):
        y = y0 + 0.15 + i * (L - 1.0) / 16
        z = bl.flat(y, 0.0)
        hgt = rnd.uniform(0.05, 0.12)
        d.fill([bl.pline([(y - 0.04, z - 0.02), (y + 0.01, z + hgt), (y + 0.05, z - 0.02)])], (255, 255, 255), alpha=200)
    flakes, moons = [], []
    for i, y in enumerate((y0 + 0.55, y0 + 1.45, y0 + 2.35)):
        zc = bl.flat(y, 0.59)
        fl = snowflake(y, zc, 0.11)
        flakes += fl
        gl(bl, fl, glow, width=5, halo=9)
    for y in (y0 + 1.0, y0 + 1.9, y0 + 2.8):
        zc = bl.flat(y, 0.59)
        moon = K.circle_poly(y, zc, 0.07, 14)
        d.fill([bl.pline(moon)], (255, 255, 255))
        d.fill([bl.pline(K.circle_poly(y + 0.03, zc + 0.03, 0.06, 14))], (150, 196, 236))
        moons.append(moon)
    bl.inlay(flakes, width=0.022)
    d.engrave([bl.pline(bl.line(0.97, y0 + 0.4, y0 + L - 0.95))], width=3, depth=140)
    bl.edge_glow()
    bl.finish((214, 234, 250), roughness=0.25)

    # big crescent moon guard with ice filigree, full-moon disc, ice crystal clusters
    yc = 0.88
    cres = crescent(0.82, 0.48, -0.26, 0.1)
    mid = [(0.74 * math.cos(math.pi + math.pi * i / 14), 0.45 - 0.5 * math.sin(math.pi * i / 14)) for i in range(15)]
    sw.plate(cres, yc, 0.26, white, bevel=0.02, roughness=0.3, paint=lambda dd, gx, gy: (
        dd.emboss([[(gx(z), gy(dy)) for z, dy in mid]], width=7, color=ice),
        [dd.engrave([P.spiral(gx(s * 0.5), gy(-0.04), 12, 3, 1.3, cw=s)], width=3, depth=130) for s in (-1, 1)]))
    sw.plate(circ_out(0.25, 24), yc + 0.06, 0.32, (200, 222, 246), bevel=0.02, paint=outline_paint(circ_out(0.25, 24), 0.82, color=ice, width=5))
    sw.ring(yc + 0.06, 0.13, 0.18, 0.36, glow=True, seg=20)
    sw.gem((0, yc + 0.06, 0), 0.1, 0.21, 6)
    for side in (-1, 1):
        hz = side * 0.78
        for (dz, ddy, ang, ln, r) in ((0, 0, 0.3, 0.34, 0.07), (-0.08, -0.02, 1.4, 0.24, 0.05), (0.05, 0.02, -0.5, 0.2, 0.045), (-0.14, -0.03, 0.9, 0.18, 0.04)):
            sw.crystal((0, yc + 0.44 + ddy, hz + side * dz), (0, math.cos(ang), side * math.sin(ang)), ln, r)
        sw.crystal((0, yc - 0.2, side * 0.3), (0, -1, side * 0.5), 0.16, 0.04)
        sw.stud((0, yc + 0.05, side * 0.5), 0.035, 0.14, ice)
    sw.box((0.2, 0.22, 0.6), (0, yc + 0.34, 0), white, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.58, 0.13, 0.17, navy, (160, 230, 255), style="ribbon", width=0.14)
    for y in (0.6, 0.0):
        sw.box((0.34, 0.12, 0.42), (0, y, 0), white, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    # pommel: little crescent moon cradling a gem, icicle below
    pc = crescent(0.28, -0.14, 0.14, -0.02, n=10)
    sw.plate(pc, -0.78, 0.26, white, bevel=0.018, paint=outline_paint(pc, 0.7, color=ice, width=4))
    sw.box((0.3, 0.16, 0.34), (0, -0.7, 0), white, bevel=0.03, roughness=0.3)
    sw.gem((0, -0.86, 0), 0.08, 0.17, 6)
    sw.crystal((0, -0.94, 0), (0, -1, 0), 0.28, 0.06)
    return sw.done()


def sunforged_katana():
    glow = (255, 255, 160)
    sw = Sword("sunforged_katana", glow, DECALS)
    rnd = P.rng(85)
    gold, pale, bronze = (255, 214, 96), (255, 236, 160), (150, 96, 22)
    y0, L, w = 1.08, 4.3, 0.56
    edge, spine = K.katana_outline(y0, L, w, clip=0.62, wf=lambda s: 1 + 0.18 * s)
    bl = Blade(sw, edge, spine, thick=0.12, bevel=0.13, kissaki=y0 + L - 0.82, bend=lambda s: 0.45 * s * s)
    d = bl.decal
    bl.paint_bevel((255, 238, 168))
    bl.paint_bevel((255, 250, 220), inset=0.6)
    ya, yb = y0 + 0.62, y0 + L - 1.0
    fullers = []
    for fa, fb in ((0.12, 0.36), (0.6, 0.84)):
        channel(bl, ya, yb, fa, fb, (170, 112, 26))
        fullers.append(bl.line((fa + fb) / 2, ya + 0.08, yb - 0.08))
    gl(bl, fullers, glow, width=6, halo=12)
    bl.inlay(fullers, width=0.03)
    # sun disc near the base: glowing core with engraved rays
    sy, sz = y0 + 0.3, bl.flat(y0 + 0.3, 0.5)
    rays = []
    for k in range(12):
        a = k * math.pi / 6
        rays.append([(sy + math.sin(a) * 0.12, sz + math.cos(a) * 0.12), (sy + math.sin(a) * 0.22, sz + math.cos(a) * 0.2)])
    d.engrave([bl.pline(r) for r in rays], width=4, depth=180)
    d.fill([bl.pline(K.circle_poly(sy, sz, 0.1, 16))], (255, 250, 200))
    bl.slab([K.circle_poly(sy, sz, 0.075, 12)])
    bl.inlay(rays[::2], width=0.02)
    for i in range(7):
        y = ya + 0.2 + i * (yb - ya - 0.3) / 6
        d.engrave([bl.pline(st) for st in K.rune_strokes(y, bl.flat(y, 0.48), 0.07, rnd)], width=3, depth=170)
    bl.edge_glow()
    bl.finish((236, 186, 62), roughness=0.25)

    # wings of gold behind a radiant sun
    yc = 0.94
    wings(sw, yc, [(0.22, 0.02, 28, 0.96, 0.24), (0.22, -0.03, 10, 0.84, 0.21), (0.22, -0.08, -10, 0.64, 0.18)], (250, 190, 44),
          trim=(255, 244, 190), fill=(236, 120, 30), thick=0.18, glow_tips=True)
    sun = star_out(0.48, 0.32, 12)
    sw.plate(sun, yc, 0.26, gold, bevel=0.016, roughness=0.3, paint=outline_paint(sun, 0.8, color=(255, 246, 200), width=5, fill=(234, 150, 40)))
    sw.plate(circ_out(0.25, 24), yc, 0.32, gold, bevel=0.02, roughness=0.3, paint=outline_paint(circ_out(0.25, 24), 0.8, color=(255, 246, 200), width=5, engrave_k=0.6))
    sw.gem((0, yc, 0), 0.17, 0.21, 8)
    for k in range(12):
        a = math.pi / 2 + k * math.pi / 6
        if abs(math.cos(a)) > 0.95:
            continue
        sw.stud((0, yc + math.sin(a) * 0.4, math.cos(a) * 0.4), 0.028, 0.14, (255, 246, 200))
    sw.box((0.22, 0.22, 0.62), (0, yc + 0.34, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.56, 0.13, 0.17, (120, 70, 10), (255, 232, 170), style="straps", width=0.17)
    for y in (0.58, -0.02):
        sw.box((0.34, 0.12, 0.42), (0, y, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    # pommel: small sun with a gem
    ps = star_out(0.26, 0.17, 10)
    sw.plate(ps, -0.84, 0.24, gold, bevel=0.015, roughness=0.3, paint=outline_paint(ps, 0.78, color=(255, 246, 200), width=4, fill=(234, 150, 40)))
    sw.box((0.3, 0.16, 0.34), (0, -0.66, 0), gold, bevel=0.03, roughness=0.3)
    sw.gem((0, -0.84, 0), 0.1, 0.17, 8)
    return sw.done()


def bloodmoon_katana():
    glow = (255, 20, 60)
    sw = Sword("bloodmoon_katana", glow, DECALS)
    rnd = P.rng(96)
    dark, red = (58, 8, 18), (255, 40, 80)
    y0, L, w = 1.08, 4.5, 0.58
    edge, spine = K.katana_outline(y0, L, w, clip=0.66, wf=lambda s: 1 + 0.08 * s,
                                   spine_pts=K.teeth(0.4, 0.84, 7, 0.065, lean=0.82))
    bl = Blade(sw, edge, spine, thick=0.12, bevel=0.14, kissaki=y0 + L - 0.86, bend=lambda s: 0.8 * s * s)
    d = bl.decal
    bl.paint_bevel((206, 30, 60))
    bl.paint_bevel((255, 110, 140), inset=0.62)
    channel(bl, y0 + 0.1, y0 + L - 1.05, 0.2, 0.92, (34, 2, 8))
    veins = []
    for (ya, yb, f) in ((y0 + 0.5, y0 + 1.7, 0.55), (y0 + 1.6, y0 + 2.7, 0.5), (y0 + 2.6, y0 + 3.4, 0.55)):
        veins += K.crack(rnd, ya, yb, lambda y, f=f: bl.flat(y, f), 0.06, n=7, branches=4, blen=0.4)
    gl(bl, veins, (255, 40, 80), width=5, halo=11)
    bl.inlay(veins, width=0.024)
    my, mz = y0 + 0.28, bl.flat(y0 + 0.28, 0.56)
    d.fill([bl.pline(K.circle_poly(my, mz, 0.13, 18))], (255, 60, 90))
    bl.slab([K.circle_poly(my, mz, 0.1, 16)])
    # thorny vine engraved along the spine
    vine = bl.line(0.95, y0 + 0.1, y0 + L - 1.0)
    d.engrave([bl.pline(vine)], width=3, depth=200, light=60)
    for i in range(0, len(vine) - 2, 3):
        y, z = vine[i]
        d.engrave([bl.pline([(y, z), (y + 0.06, z - 0.04)])], width=3, depth=200, light=60)
    bl.edge_glow()
    bl.finish((80, 16, 28), roughness=0.25)

    # eclipse guard: glowing blood moon disc behind a thorned black guard
    yc = 0.92
    sw.plate(circ_out(0.5, 32), yc + 0.2, 0.18, None, glow=True, bevel=0.01)
    sw.ring(yc + 0.2, 0.49, 0.56, 0.24, (40, 0, 8), seg=32)
    half = [(0, 0.16), (0.12, 0.18), (0.24, 0.44), (0.3, 0.14), (0.48, 0.34), (0.46, 0.08), (0.72, 0.16), (0.56, -0.04),
            (0.66, -0.24), (0.4, -0.12), (0.26, -0.3), (0.16, -0.14), (0, -0.2)]
    g = sym(half)
    sw.plate(g, yc, 0.3, (50, 6, 14), bevel=0.018, paint=outline_paint(g, 0.74, color=(220, 40, 70), width=5))
    for side in (-1, 1):
        for (z, dy) in ((0.24, 0.44), (0.48, 0.34), (0.72, 0.16), (0.66, -0.24), (0.26, -0.3)):
            sw.crystal((0, yc + dy * 0.8, side * z * 0.85), (0, dy, side * z), 0.12, 0.028, sides=4)
        sw.gem((0, yc + 0.02, side * 0.36), 0.05, 0.17, 4)
    sw.ring(yc + 0.02, 0.12, 0.2, 0.36, (40, 0, 8), seg=16)
    sw.gem((0, yc + 0.02, 0), 0.12, 0.21, 6)
    sw.box((0.22, 0.22, 0.64), (0, yc + 0.34, 0), (50, 6, 14), bevel=0.02, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.6, 0.13, 0.17, (24, 0, 6), red, style="ribbon", width=0.14)
    for y in (0.6, 0.0):
        sw.box((0.34, 0.12, 0.42), (0, y, 0), (50, 6, 14), bevel=0.02, paint=engraved_block(spirals=2))
    sw.box((0.36, 0.24, 0.46), (0, -0.74, 0), (50, 6, 14), bevel=0.035, paint=engraved_block(rings=1, color=(220, 40, 70), spirals=0))
    for side in (-1, 1):
        sw.spike((0, -0.74, side * 0.22), (0, -0.5, side), 0.2, 0.06, (40, 0, 8))
    sw.gem((0, -0.74, 0), 0.08, 0.2, 6)
    sw.tassel((0, -0.86, 0), (220, 20, 50), length=0.7, lean=-0.22, cord_rgb=(40, 0, 8))
    return sw.done()


def umbra_katana():
    glow = (170, 90, 255)
    sw = Sword("umbra_katana", glow, DECALS)
    rnd = P.rng(107)
    violet, dark = (90, 40, 180), (26, 12, 48)
    y0, L, w = 1.08, 4.6, 0.58
    edge, spine = K.katana_outline(y0, L, w, clip=0.72, tip="hook", hook=0.12, wf=lambda s: 1 + 0.06 * s,
                                   spine_pts=K.waves(0.12, 0.78, 3, 0.04))
    bl = Blade(sw, edge, spine, thick=0.12, bevel=0.14, kissaki=y0 + L - 0.92, bend=lambda s: 0.7 * s * s)
    d = bl.decal
    bl.paint_bevel((128, 80, 210))
    bl.paint_bevel((196, 160, 255), inset=0.62)
    ya, yb = y0 + 0.62, y0 + L - 1.06
    lines = []
    for fa, fb in ((0.12, 0.34), (0.62, 0.84)):
        channel(bl, ya, yb, fa, fb, (12, 4, 26))
        lines.append(bl.line((fa + fb) / 2, ya + 0.06, yb - 0.06))
    gl(bl, lines, glow, width=6, halo=12)
    bl.inlay(lines, width=0.03)
    # shadow wisps curling off the fullers
    for i in range(6):
        y = ya + 0.3 + i * 0.5
        z = bl.flat(y, 0.48)
        d.engrave([P.spiral(*bl.px(y, z), 14, 2, 1.4, cw=1 if i % 2 else -1)], width=3, depth=60, light=150)
    # the eye near the base
    ey, ez = y0 + 0.3, bl.flat(y0 + 0.3, 0.5)
    eye = [(ey + 0.0, ez - 0.17), (ey + 0.08, ez - 0.06), (ey + 0.09, ez + 0.06), (ey, ez + 0.17), (ey - 0.09, ez + 0.06), (ey - 0.08, ez - 0.06)]
    d.fill([bl.pline(eye)], (200, 150, 255))
    d.fill([bl.pline(K.circle_poly(ey, ez, 0.05, 12))], (12, 4, 26))
    bl.inlay([eye + [eye[0]]], width=0.022)
    bl.slab([K.diamond_poly(ey, ez, 0.06, 0.025)])
    bl.edge_glow()
    bl.finish((46, 30, 74), roughness=0.2)

    # halo ring standing on a dark guard bar, joined by spokes, glowing inner ring
    yc = 0.86
    bar = [(0.44, 0.12), (0.56, 0.0), (0.44, -0.14), (-0.44, -0.14), (-0.56, 0.0), (-0.44, 0.12)]
    sw.plate(bar, yc, 0.28, violet, bevel=0.02, paint=outline_paint(bar, 0.8, color=(200, 160, 255), width=5))
    ry = 1.4
    rune_paint = lambda dd, gx, gy: [dd.glow([[(gx(z), gy(dy)) for z, dy in [(0.47 * math.cos(a) + c[0] * 0.05, 0.47 * math.sin(a) + c[1] * 0.05) for c in st]] for st in [[(-0.6, -1), (0, 1)], [(0, 1), (0.6, -1)], [(-0.3, 0), (0.3, 0)]]], (200, 150, 255), width=4, halo=6) for a in [k * math.pi / 5 for k in range(10)]]
    sw.ring(ry, 0.38, 0.56, 0.22, violet, seg=32, paint=rune_paint)
    sw.ring(ry, 0.33, 0.39, 0.12, glow=True, seg=32)
    for k in range(8):
        a = math.pi / 8 + k * math.pi / 4
        if math.sin(a) < -0.5:
            continue
        sw.spike((0, ry + math.sin(a) * 0.54, math.cos(a) * 0.54), (0, math.sin(a), math.cos(a)), 0.18, 0.05, dark)
    for side in (-1, 1):
        sw.gem((0, yc, side * 0.42), 0.05, 0.16, 4)
    sw.ring(yc, 0.1, 0.17, 0.34, dark, seg=16)
    sw.gem((0, yc, 0), 0.1, 0.2, 6)
    sw.box((0.2, 0.22, 0.62), (0, yc + 0.22, 0), dark, bevel=0.02, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.66, 0.13, 0.17, (8, 4, 16), (150, 70, 255), style="straps", width=0.17)
    sw.box((0.34, 0.12, 0.42), (0, 0.68, 0), dark, bevel=0.02, paint=engraved_block(spirals=2))
    # ring pommel with a gem floating in it
    sw.box((0.32, 0.14, 0.38), (0, -0.7, 0), violet, bevel=0.03)
    sw.ring(-0.95, 0.12, 0.2, 0.2, violet, seg=20)
    sw.ring(-0.95, 0.09, 0.125, 0.1, glow=True, seg=20)
    sw.gem((0, -0.95, 0), 0.06, 0.08, 6)
    return sw.done()


def starfall_katana():
    glow = (140, 220, 255)
    sw = Sword("starfall_katana", glow, DECALS)
    rnd = P.rng(118)
    gold, navy = (255, 222, 120), (30, 40, 100)
    y0, L, w = 1.1, 4.7, 0.6
    edge, spine = K.katana_outline(y0, L, w, clip=0.66, wf=lambda s: 1 + 0.1 * s,
                                   spine_pts=K.teeth(0.5, 0.82, 3, 0.06, lean=0.5))
    bl = Blade(sw, edge, spine, thick=0.12, bevel=0.14, kissaki=y0 + L - 0.88, bend=lambda s: 0.5 * s * s)
    d = bl.decal
    bl.paint_bevel((255, 210, 100))
    bl.paint_bevel((255, 242, 190), inset=0.6)
    ya, yb = y0 + 0.1, y0 + L - 1.02
    channel(bl, ya, yb, 0.12, 0.9, (26, 36, 96))
    d.engrave([bl.pline(bl.line(0.12, ya, yb)), bl.pline(bl.line(0.9, ya, yb))], width=4, depth=60, light=200)
    for i in range(90):
        y = rnd.uniform(ya + 0.05, yb - 0.05)
        z = bl.flat(y, rnd.uniform(0.18, 0.84))
        x, yy = bl.px(y, z)
        r = rnd.choice((1.2, 1.6, 2.2))
        d.fill([[(x - r, yy), (x, yy - r), (x + r, yy), (x, yy + r)]], (255, 255, 255), alpha=230, blur=0.4)
    stars, pts = [], []
    for i in range(6):
        y = ya + 0.25 + i * (yb - ya - 0.4) / 5
        z = bl.flat(y, 0.35 if i % 2 == 0 else 0.68)
        pts.append((y, z))
        stars.append(K.star_poly(y, z, 0.1 if i % 2 == 0 else 0.075, 0.03, 4))
    gl(bl, [pts], glow, width=3, halo=8)
    for st in stars:
        d.fill([bl.pline(st)], (220, 245, 255))
    bl.slab(stars, raise_=0.016)
    bl.inlay([pts], width=0.014, raise_=0.008)
    bl.edge_glow()
    bl.finish((176, 214, 246), roughness=0.2)

    # golden feathered wings, star crest, floating stars
    yc = 0.96
    wings(sw, yc, [(0.18, 0.02, 34, 0.86, 0.22), (0.2, -0.02, 16, 0.8, 0.2), (0.2, -0.06, -2, 0.66, 0.18), (0.18, -0.1, -20, 0.48, 0.15)],
          (246, 190, 50), trim=(255, 248, 220), fill=(44, 64, 150), thick=0.2, glow_tips=True)
    st8 = star_out(0.36, 0.17, 8)
    sw.plate(st8, yc, 0.3, navy, bevel=0.016, paint=outline_paint(st8, 0.84, color=gold, width=5))
    sw.plate(circ_out(0.17, 20), yc, 0.34, gold, bevel=0.02, roughness=0.3)
    sw.gem((0, yc, 0), 0.14, 0.21, 8)
    for side in (-1, 1):
        for (z, dy, r) in ((0.98, 0.72, 0.09), (0.72, 0.98, 0.065), (1.08, 0.36, 0.055)):
            sw.plate(star_out(r, r * 0.38, 4), yc + dy, 0.07, None, glow=True, bevel=0.0, zc=side * z)
    sw.box((0.22, 0.22, 0.66), (0, yc + 0.34, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.6, 0.13, 0.17, navy, (255, 226, 140), style="straps", width=0.17)
    for y in (0.62, 0.0):
        sw.box((0.34, 0.12, 0.42), (0, y, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    ps = star_out(0.3, 0.13, 8)
    sw.plate(ps, -0.86, 0.24, gold, bevel=0.015, roughness=0.3, paint=outline_paint(ps, 0.75, color=(255, 248, 220), width=4, fill=navy))
    sw.box((0.3, 0.16, 0.34), (0, -0.68, 0), gold, bevel=0.03, roughness=0.3)
    sw.gem((0, -0.86, 0), 0.09, 0.17, 8)
    sw.plate(star_out(0.08, 0.03, 4), -1.3, 0.07, None, glow=True, bevel=0.0)
    return sw.done()


def oblivion_katana():
    glow = (255, 120, 255)
    sw = Sword("oblivion_katana", glow, DECALS)
    rnd = P.rng(129)
    void, mag = (34, 10, 50), (200, 60, 255)
    y0, L, w = 1.12, 5.0, 0.64
    edge, spine = K.katana_outline(y0, L, w, clip=0.76, tip="hook", hook=0.14, wf=lambda s: 1 + 0.08 * s,
                                   spine_pts=K.teeth(0.3, 0.84, 6, 0.075, lean=0.55, jitter=0.5, rnd=rnd))
    bl = Blade(sw, edge, spine, thick=0.13, bevel=0.15, kissaki=y0 + L - 0.98, bend=lambda s: 0.85 * s * s)
    d = bl.decal
    bl.paint_bevel((170, 50, 220))
    bl.paint_bevel((246, 150, 255), inset=0.62)
    ya, yb = y0 + 0.12, y0 + L - 1.06
    channel(bl, ya, yb, 0.08, 0.94, (10, 0, 22), depth=60)
    # the rift: a jagged tear of light down the middle, runes on both sides
    rift = []
    n = 14
    for i in range(n + 1):
        y = ya + 0.05 + (yb - ya - 0.1) * i / n
        rift.append((y, bl.flat(y, 0.5 + (rnd.uniform(-0.12, 0.12) if 0 < i < n else 0))))
    widths = [0.012 if i in (0, n) else rnd.uniform(0.035, 0.06) for i in range(n + 1)]
    poly = [(y, z + wd) for (y, z), wd in zip(rift, widths)] + [(y, z - wd) for (y, z), wd in reversed(list(zip(rift, widths)))]
    d.glow([bl.pline(rift)], (255, 140, 255), width=22, halo=22)
    d.fill([bl.pline(poly)], (255, 230, 255))
    bl.slab([poly], raise_=0.016)
    branches = []
    for i in range(1, n, 2):
        y, z = rift[i]
        side = 1 if i % 4 == 1 else -1
        branches.append([(y, z), (y + 0.12, z + side * 0.1), (y + 0.2, z + side * 0.13)])
    gl(bl, branches, glow, width=4, halo=8)
    bl.inlay(branches, width=0.02)
    for i in range(7):
        y = ya + 0.3 + i * (yb - ya - 0.5) / 6
        for f in (0.2, 0.82):
            gl(bl, K.rune_strokes(y + (0.15 if f > 0.5 else 0), bl.flat(y, f), 0.08, rnd), (255, 150, 255), width=4, halo=7)
    bl.edge_glow()
    bl.finish((36, 14, 54), roughness=0.2)

    # portal ring standing on a spiked void guard, orbiting shards
    yc = 0.88
    half = [(0, 0.14), (0.3, 0.14), (0.5, 0.3), (0.52, 0.1), (0.76, 0.12), (0.6, -0.04), (0.7, -0.24), (0.42, -0.14), (0.2, -0.22), (0, -0.16)]
    g = sym(half)
    sw.plate(g, yc, 0.3, void, bevel=0.018, paint=outline_paint(g, 0.76, color=mag, width=5))
    ry = 1.5
    rp = lambda dd, gx, gy: (dd.engrave([[(gx(0.56 * math.cos(a)), gy(0.56 * math.sin(a))) for a in [k * math.pi / 24 for k in range(49)]]], width=4, depth=80, light=160),
                             [dd.glow([[(gx(z), gy(dy)) for z, dy in [(0.56 * math.cos(a) + c[0] * 0.05, 0.56 * math.sin(a) + c[1] * 0.05) for c in st]] for st in [[(-0.7, -1), (0.7, 1)], [(0.7, -1), (-0.7, 1)], [(0, -1), (0, 1)]]], (255, 150, 255), width=4, halo=6) for a in [k * math.pi / 6 for k in range(12)]])
    sw.ring(ry, 0.46, 0.68, 0.24, (60, 20, 90), seg=36, paint=rp)
    sw.ring(ry, 0.39, 0.47, 0.13, glow=True, seg=36)
    for k in range(10):
        a = math.pi / 10 + k * math.pi / 5
        if math.sin(a) < -0.6:
            continue
        r = 0.78
        sw.crystal((0, ry + math.sin(a) * r, math.cos(a) * r), (0, math.sin(a), math.cos(a)), 0.2 if k % 2 else 0.14, 0.05, sides=4)
    for side in (-1, 1):
        sw.crystal((0, yc + 0.1, side * 0.74), (0, 0.3, side), 0.2, 0.05, sides=4)
        sw.gem((0, yc, side * 0.42), 0.055, 0.17, 4)
    sw.ring(yc, 0.12, 0.2, 0.36, void, seg=16)
    sw.gem((0, yc, 0), 0.12, 0.21, 6)
    sw.box((0.22, 0.24, 0.7), (0, yc + 0.26, 0), void, bevel=0.02, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.68, 0.13, 0.17, (12, 0, 22), (230, 80, 255), style="straps", width=0.17)
    sw.box((0.34, 0.12, 0.42), (0, 0.7, 0), void, bevel=0.02, paint=engraved_block(spirals=2))
    # pommel: void orb in a spiked cage
    sw.box((0.34, 0.16, 0.4), (0, -0.7, 0), void, bevel=0.03)
    sw.ring(-0.98, 0.16, 0.24, 0.2, (60, 20, 90), seg=20)
    sw.gem((0, -0.98, 0), 0.12, 0.12, 8, dome=1.0)
    for k in range(5):
        a = -math.pi / 2 + (k - 2) * 0.6
        sw.crystal((0, -0.98 + math.sin(a) * 0.26, math.cos(a) * 0.26), (0, math.sin(a), math.cos(a)), 0.14, 0.035, sides=4)
    return sw.done()


# ====================================================================== shop swords
def oak_fang():
    sw = Sword("oak_fang", None, DECALS)
    rnd = P.rng(131)
    wood, bone, iron = (122, 86, 44), (238, 226, 196), (84, 84, 92)
    y0, L, w = 1.0, 3.6, 0.46
    fang = [(0.7, 0.0), (0.78, 0.13), (0.787, 0.03), (0.8, 0.0)]
    edge, spine = K.katana_outline(y0, L, w, clip=0.5, wf=lambda s: 1 + 0.06 * s, spine_pts=fang)
    bl = Blade(sw, edge, spine, thick=0.1, bevel=0.12, kissaki=y0 + L - 0.68, bend=lambda s: 0.3 * s * s)
    d = bl.decal
    bl.paint_bevel((236, 238, 244))
    for f in (0.72, 0.84):
        d.engrave([bl.pline(bl.line(f, y0 + 0.1, y0 + L - 1.15))], width=5, depth=190)
    # oak leaf and acorn engraved near the base, wolf-fang notches up the blade
    ly, lz = y0 + 0.42, bl.flat(y0 + 0.42, 0.42)
    lf = [(ly + 0.2 * t, lz + 0.07 * math.sin(math.pi * t) * (1 + 0.35 * math.sin(t * 5 * math.pi))) for t in [i / 16 for i in range(17)]]
    lf += [(ly + 0.2 * t, lz - 0.07 * math.sin(math.pi * t) * (1 + 0.35 * math.sin(t * 5 * math.pi))) for t in [i / 16 for i in range(16, -1, -1)]]
    d.engrave([bl.pline(lf), bl.pline([(ly - 0.05, lz), (ly + 0.2, lz)])], width=3, depth=180)
    for i in range(4):
        y = y0 + 0.9 + i * 0.42
        z = bl.flat(y, 0.42)
        d.engrave([bl.pline([(y - 0.06, z - 0.04), (y + 0.06, z), (y - 0.06, z + 0.04)])], width=4, depth=180)
    bl.finish((212, 214, 222))

    # chunky oak guard with bone fangs and iron studs
    yc = 0.84
    blk = [(0.36, 0.16), (0.42, 0.1), (0.42, -0.12), (0.36, -0.18), (-0.36, -0.18), (-0.42, -0.12), (-0.42, 0.1), (-0.36, 0.16)]

    def grain(dd, gx, gy):
        for k in range(5):
            r = 0.08 + k * 0.08
            dd.engrave([[(gx(math.cos(a) * r * 1.6), gy(math.sin(a) * r * 0.45 - 0.01)) for a in [j * math.pi / 20 for j in range(41)]]], width=2, depth=110)
        dd.engrave([[(gx(z), gy(dy)) for z, dy in inset(blk, 0.86)]], width=4, depth=150, closed=True)
    sw.plate(blk, yc, 0.3, wood, bevel=0.03, paint=grain, noise=0.08)
    for side in (-1, 1):
        sw.box((0.4, 0.42, 0.24), (0, yc - 0.01, side * 0.52), wood, bevel=0.035, noise=0.08, paint=engraved_block(spirals=0, rings=2, color=bone))
        sw.crystal((0, yc + 0.18, side * 0.5), (0, 1, side * 0.4), 0.42, 0.075, rgb=bone, sides=5, glow=False, tip=0.6)
        sw.crystal((0, yc + 0.1, side * 0.24), (0, 1, side * 0.12), 0.24, 0.05, rgb=bone, sides=5, glow=False, tip=0.6)
        for dy in (0.05, -0.08):
            sw.stud((0, yc + dy, side * 0.4), 0.03, 0.16, iron)
    sw.box((0.2, 0.2, 0.52), (0, yc + 0.22, 0), iron, bevel=0.02, roughness=0.4, paint=engraved_block(spirals=0, key=True))
    sw.grip(-0.62, 0.66, 0.14, 0.18, (100, 66, 34), (44, 32, 22), style="straps", width=0.18)
    sw.box((0.34, 0.12, 0.42), (0, 0.67, 0), iron, bevel=0.02)
    sw.box((0.4, 0.26, 0.5), (0, -0.78, 0), wood, bevel=0.04, noise=0.08, paint=engraved_block(spirals=0, rings=1, color=bone))
    sw.box((0.42, 0.06, 0.52), (0, -0.66, 0), iron, bevel=0.015)
    sw.tassel((0, -0.92, 0), (200, 60, 40), length=0.6, lean=-0.18, cord_rgb=(44, 32, 22), glow_bead=False)
    return sw.done()


def viper_edge():
    glow = (170, 255, 60)
    sw = Sword("viper_edge", glow, DECALS)
    rnd = P.rng(142)
    green, dark, lime = (58, 100, 60), (30, 54, 32), (170, 255, 60)
    y0, L, w = 1.02, 3.8, 0.44
    wv = K.waves(0.08, 0.78, 4, 0.045)
    edge, spine = K.katana_outline(y0, L, w, clip=0.56, tip="center", wf=lambda s: 1 + 0.05 * s, spine_pts=wv,
                                   edge_pts=[(s, -dz) for s, dz in wv])
    bl = Blade(sw, edge, spine, thick=0.1, bevel=0.11, kissaki=y0 + L - 0.74, bend=lambda s: 0.7 * s * s)
    d = bl.decal
    bl.paint_bevel((150, 196, 110))
    bl.paint_bevel((206, 240, 160), inset=0.6)
    # snake scales over the flat, a venom channel down the middle
    for i in range(46):
        y = y0 + 0.08 + i * 0.065
        if y > y0 + L - 0.8:
            break
        for f in ((0.2, 0.5, 0.8) if i % 2 == 0 else (0.35, 0.65)):
            z = bl.flat(y, f)
            d.engrave([bl.pline([(y - 0.03, z - 0.045), (y + 0.035, z), (y - 0.03, z + 0.045)])], width=3, depth=150, light=70)
    ya, yb = y0 + 0.15, y0 + L - 0.95
    channel(bl, ya, yb, 0.44, 0.56, (24, 40, 26))
    vl = bl.line(0.5, ya + 0.05, yb - 0.05)
    gl(bl, [vl], lime, width=5, halo=10)
    bl.inlay([vl], width=0.02)
    drops = []
    for i in range(5):
        y = ya + 0.3 + i * (yb - ya - 0.5) / 4
        drops.append(K.flame_poly(y, bl.flat(y, 0.5), 0.17, 0.08))
        d.fill([bl.pline(K.flame_poly(y, bl.flat(y, 0.5), 0.22, 0.11))], (24, 40, 26))
    bl.slab(drops)
    bl.finish((64, 98, 64), roughness=0.3)

    # twin snake-head guard with fangs and glowing eyes
    yc = 0.86
    half = [(z * 1.2, dy * 1.3) for z, dy in [(0, 0.15), (0.26, 0.13), (0.42, 0.26), (0.6, 0.24), (0.68, 0.14), (0.48, 0.06), (0.66, -0.04), (0.6, -0.12),
                                            (0.42, -0.16), (0.2, -0.14), (0, -0.16)]]
    g = sym(half)

    def scales(dd, gx, gy):
        dd.fill([[(gx(z), gy(dy)) for z, dy in inset(g, 0.8)]], (40, 76, 42))
        for k in range(-9, 10):
            for j in range(-2, 3):
                z, dy = k * 0.07 + (0.035 if j % 2 else 0), j * 0.07
                dd.engrave([[(gx(z - 0.035), gy(dy + 0.02)), (gx(z), gy(dy - 0.03)), (gx(z + 0.035), gy(dy + 0.02))]], width=2, depth=120)
        dd.emboss([[(gx(z), gy(dy)) for z, dy in inset(g, 0.86)]], width=4, color=lime, closed=True)
    sw.plate(g, yc, 0.28, green, bevel=0.018, paint=scales)
    for side in (-1, 1):
        sw.gem((0, yc + 0.22, side * 0.62), 0.055, 0.15, 4, roll=0.0)
        for (z, dy, dz, ddy, ln) in ((0.72, 0.1, -0.2, -1, 0.15), (0.65, 0.12, -0.1, -1, 0.11), (0.72, -0.03, 0.0, 1, 0.1)):
            sw.spike((0, yc + dy, side * z), (0, ddy, side * dz), ln, 0.03, (240, 236, 220), sides=4)
        sw.spike((0, yc + 0.31, side * 0.48), (0, 0.6, -side * 0.6), 0.18, 0.05, dark)
    sw.gem((0, yc, 0), 0.1, 0.18, 6)
    sw.setting((0, yc, 0), 0.13, 0.15, dark)
    sw.box((0.2, 0.2, 0.5), (0, yc + 0.24, 0), dark, bevel=0.02, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.66, 0.13, 0.17, (20, 30, 20), lime, style="straps", width=0.16)
    sw.box((0.34, 0.12, 0.42), (0, 0.67, 0), dark, bevel=0.02)
    # pommel: gem with a coiled snake tail
    sw.box((0.34, 0.24, 0.42), (0, -0.76, 0), green, bevel=0.035, paint=engraved_block(spirals=0, rings=1, color=lime))
    sw.gem((0, -0.76, 0), 0.08, 0.18, 6)
    tail = [(0, -0.86, 0), (0, -1.0, -0.06), (0, -1.08, 0.06), (0, -1.02, 0.18), (0, -0.94, 0.16), (0, -0.96, 0.08)]
    sw.tube(tail, 0.07, green, sides=6, taper=lambda t: 1 - 0.8 * t)
    return sw.done()


def stormcaller():
    glow = (160, 200, 255)
    sw = Sword("stormcaller", glow, DECALS)
    rnd = P.rng(153)
    blue, steel, silver = (64, 86, 170), (222, 230, 250), (210, 216, 232)
    y0, L, w = 1.04, 4.0, 0.5
    notch = [(0.58, 0.0), (0.6, 0.06), (0.66, 0.0), (0.7, 0.06), (0.76, 0.0)]
    edge, spine = K.katana_outline(y0, L, w, clip=0.58, wf=lambda s: 1 + 0.08 * s, spine_pts=notch)
    bl = Blade(sw, edge, spine, thick=0.11, bevel=0.13, kissaki=y0 + L - 0.78, bend=lambda s: 0.38 * s * s)
    d = bl.decal
    bl.paint_bevel((196, 214, 255))
    ya, yb = y0 + 0.35, y0 + L - 1.05
    channel(bl, y0 + 0.1, yb + 0.12, 0.1, 0.92, (70, 84, 130))
    bolt = bolt_poly(bl, ya, yb, 0.22, 0.78, 6, 0.08)
    d.glow([bl.pline(bolt + [bolt[0]])], (180, 210, 255), width=8, halo=16)
    d.fill([bl.pline(bolt)], (240, 248, 255))
    bl.slab([bolt])
    # storm clouds engraved round the base and up the spine
    for k, (y, f) in enumerate(((y0 + 0.2, 0.3), (y0 + 0.22, 0.6), (y0 + 0.18, 0.86))):
        d.engrave([P.spiral(*bl.px(y, bl.flat(y, f)), 14, 2, 1.3, cw=1 if k % 2 else -1)], width=3, depth=60, light=170)
    bl.edge_glow()
    bl.finish((222, 230, 250), roughness=0.3)

    # storm-cloud wings with zigzag undersides and lightning inlays
    yc = 0.88
    half = [(0, 0.18), (0.2, 0.2), (0.5, 0.36), (0.84, 0.54), (0.68, 0.32), (0.78, 0.24), (0.58, 0.14), (0.64, 0.02),
            (0.42, -0.04), (0.46, -0.16), (0.24, -0.12), (0, -0.16)]
    g = sym(half)
    sw.plate(g, yc, 0.26, blue, bevel=0.018, paint=outline_paint(g, 0.8, color=silver, width=5,
                                                                    spirals=((0.3, 0.06, 12, 1), (-0.3, 0.06, 12, -1))))
    for side in (-1, 1):
        zz = [(0.38, 0.22), (0.5, 0.16), (0.56, 0.3), (0.7, 0.36)]
        bp = [(side * z, dy + 0.025) for z, dy in zz] + [(side * z, dy - 0.025) for z, dy in reversed(zz)]
        if side < 0:
            bp = list(reversed(bp))
        sw.plate(bp, yc, 0.29, None, glow=True, bevel=0.0)
    sw.setting((0, yc + 0.02, 0), 0.15, 0.15, silver, segments=8)
    sw.gem((0, yc + 0.02, 0), 0.12, 0.18, 8)
    sw.box((0.2, 0.22, 0.56), (0, yc + 0.28, 0), silver, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.66, 0.13, 0.17, (20, 20, 40), (120, 170, 255), style="straps", width=0.17)
    for y in (0.67, 0.02):
        sw.box((0.34, 0.12, 0.42), (0, y, 0), silver, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    sw.box((0.34, 0.26, 0.44), (0, -0.77, 0), blue, bevel=0.035, paint=engraved_block(spirals=0, rings=1, color=silver))
    sw.gem((0, -0.77, 0), 0.08, 0.18, 8)
    for a in (-0.7, 0.0, 0.7):
        sw.spike((0, -0.9, math.sin(a) * 0.12), (0, -1, math.sin(a) * 1.2), 0.18, 0.04, silver)
    return sw.done()


def demonbane():
    glow = (255, 60, 60)
    sw = Sword("demonbane", glow, DECALS)
    rnd = P.rng(164)
    red, gold, paper = (200, 30, 40), (240, 186, 52), (246, 236, 206)
    y0, L, w = 1.06, 4.2, 0.56
    edge, spine = K.katana_outline(y0, L, w, clip=0.6, wf=lambda s: 1 + 0.06 * s)
    bl = Blade(sw, edge, spine, thick=0.11, bevel=0.13, kissaki=y0 + L - 0.8, bend=lambda s: 0.4 * s * s)
    d = bl.decal
    bl.paint_bevel((255, 228, 150))
    bl.paint_bevel((255, 246, 214), inset=0.6)
    for f in (0.86, 0.95):
        d.engrave([bl.pline(bl.line(f, y0 + 0.1, y0 + L - 1.0))], width=4, depth=190)
    seals = []
    for (ya, yb) in ((y0 + 0.2, y0 + 1.45), (y0 + 1.75, y0 + 3.0)):
        poly = bl.band_poly(ya, yb, 0.08, 0.76)
        d.fill([poly], paper)
        d.engrave([poly + [poly[0]]], width=3, depth=150)
        for col in (0.25, 0.55):
            for i in range(5):
                y = ya + 0.2 + i * 0.16
                d.engrave([bl.pline(st) for st in K.rune_strokes(y, bl.flat(y, col), 0.06, rnd)], width=4, depth=230, light=0)
        sy = yb - 0.2
        sz = bl.flat(sy, 0.42)
        d.fill([bl.pline(K.circle_poly(sy, sz, 0.12, 18))], (210, 30, 40))
        ring = K.circle_poly(sy, sz, 0.1, 18)
        seals.append(ring + [ring[0]])
        seals += K.rune_strokes(sy, sz, 0.08, rnd)
    gl(bl, seals, glow, width=4, halo=8)
    bl.inlay(seals, width=0.02)
    bl.finish((236, 236, 242), roughness=0.3)

    # red lotus guard with gold rims
    yc = 0.88
    bowl = crescent(0.56, 0.04, -0.26, -0.1, n=12)
    sw.plate(bowl, yc, 0.32, gold, bevel=0.02, roughness=0.3, paint=outline_paint(bowl, 0.8, color=(255, 230, 150), width=4))
    for i, (ang, ln, wd) in enumerate(((90, 0.66, 0.36), (60, 0.7, 0.32), (30, 0.68, 0.28), (4, 0.58, 0.22))):
        for side in ((1,) if ang == 90 else (1, -1)):
            a = math.radians(ang if side > 0 else 180 - ang)
            out = leaf(0, -0.04, a, ln, wd)
            sw.plate(out, yc, 0.28 - 0.035 * i, red, bevel=0.016,
                     paint=feather_paint(out, 0, -0.04, a, ln, color=gold, fill=None))
    sw.setting((0, yc + 0.02, 0), 0.14, 0.17, gold, segments=8)
    sw.gem((0, yc + 0.02, 0), 0.11, 0.2, 8)
    sw.box((0.22, 0.22, 0.6), (0, yc + 0.3, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.66, 0.13, 0.17, (34, 10, 10), (255, 240, 200), style="straps", width=0.17)
    for y in (0.67, 0.02):
        sw.box((0.34, 0.12, 0.42), (0, y, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    sw.box((0.36, 0.24, 0.46), (0, -0.76, 0), red, bevel=0.035, paint=engraved_block(spirals=0, rings=1, color=gold))
    sw.gem((0, -0.76, 0), 0.08, 0.2, 8)
    sw.tassel((0, -0.88, 0), (220, 40, 40), length=0.62, lean=-0.2, cord_rgb=gold)
    return sw.done()


def nightglass():
    glow = (120, 255, 220)
    sw = Sword("nightglass", glow, DECALS)
    rnd = P.rng(175)
    teal, navy = (60, 200, 180), (26, 28, 60)
    y0, L, w = 1.08, 4.4, 0.54
    facets = [(0.18, 0.0), (0.32, 0.035), (0.46, -0.01), (0.6, 0.04), (0.74, 0.0)]
    edge, spine = K.katana_outline(y0, L, w, clip=0.72, tip="center", wf=lambda s: 1 + 0.05 * s, spine_pts=facets,
                                   edge_pts=[(0.4, 0.02), (0.66, -0.005)])
    bl = Blade(sw, edge, spine, thick=0.12, bevel=0.14, kissaki=y0 + L - 0.9, bend=lambda s: 0.6 * s * s)
    d = bl.decal
    bl.paint_bevel((104, 136, 200))
    bl.paint_bevel((190, 236, 246), inset=0.62)
    ya, yb = y0 + 0.08, y0 + L - 1.0
    channel(bl, ya, yb, 0.04, 0.96, (22, 22, 56), depth=60)
    for i in range(110):
        y = rnd.uniform(ya + 0.05, yb - 0.02)
        x, yy = bl.px(y, bl.flat(y, rnd.uniform(0.1, 0.92)))
        r = rnd.choice((1.0, 1.4, 2.0))
        d.fill([[(x - r, yy), (x, yy - r), (x + r, yy), (x, yy + r)]], (255, 255, 255), alpha=220, blur=0.4)
    aur = [sinuous(bl, ya + 0.1, yb - 0.1, 0.5, 0.26, 2.5, phase=0.0), sinuous(bl, ya + 0.1, yb - 0.1, 0.5, 0.26, 2.5, phase=math.pi * 0.9)]
    gl(bl, aur, glow, width=6, halo=16)
    bl.inlay(aur, width=0.022)
    stars = [K.star_poly(y, bl.flat(y, f), 0.07, 0.022, 4) for y, f in ((y0 + 0.6, 0.2), (y0 + 1.5, 0.82), (y0 + 2.3, 0.18), (y0 + 3.0, 0.78))]
    for st in stars:
        d.fill([bl.pline(st)], (220, 255, 245))
    bl.slab(stars)
    bl.edge_glow()
    bl.finish((50, 52, 100), roughness=0.15)

    # round night-sky tsuba rimmed in teal, crystal shards radiating out
    yc = 0.9
    disc = circ_out(0.42, 32)

    def sky(dd, gx, gy):
        dd.fill([[(gx(z), gy(dy)) for z, dy in inset(disc, 0.84)]], navy)
        for i in range(40):
            a, r = rnd.uniform(0, 6.28), rnd.uniform(0.05, 0.33)
            x, y = gx(math.cos(a) * r), gy(math.sin(a) * r)
            dd.fill([[(x - 2, y), (x, y - 2), (x + 2, y), (x, y + 2)]], (255, 255, 255))
        dd.emboss([[(gx(z), gy(dy)) for z, dy in inset(disc, 0.84)]], width=5, color=(150, 255, 230), closed=True)
    sw.plate(disc, yc, 0.24, teal, bevel=0.02, paint=sky)
    sw.ring(yc, 0.4, 0.47, 0.3, teal, seg=32)
    for k in range(6):
        a = math.pi / 6 + k * math.pi / 3
        if abs(math.cos(a)) < 0.2:
            continue
        r = 0.46
        for j, (da, ln) in enumerate(((0, 0.24), (0.22, 0.14), (-0.22, 0.12))):
            sw.crystal((0, yc + math.sin(a) * r, math.cos(a) * r), (0, math.sin(a + da), math.cos(a + da)), ln, 0.05 - 0.012 * j)
    sw.setting((0, yc, 0), 0.13, 0.15, teal, segments=6)
    sw.gem((0, yc, 0), 0.1, 0.18, 6)
    sw.box((0.2, 0.22, 0.58), (0, yc + 0.32, 0), teal, bevel=0.02, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.52, 0.13, 0.17, (10, 10, 20), (120, 255, 220), style="ribbon", width=0.14)
    sw.box((0.34, 0.12, 0.42), (0, 0.0, 0), teal, bevel=0.02, paint=engraved_block(spirals=2))
    # pommel: teal cap with a crystal cluster
    sw.box((0.34, 0.2, 0.42), (0, -0.74, 0), teal, bevel=0.035, paint=engraved_block(spirals=0, rings=1, color=navy))
    for (dz, ln, r) in ((0, 0.34, 0.08), (0.12, 0.22, 0.055), (-0.12, 0.2, 0.05)):
        sw.crystal((0, -0.82, dz), (0, -1, dz * 3), ln, r)
    return sw.done()


def ragnablade():
    glow = (255, 220, 80)
    sw = Sword("ragnablade", glow, DECALS)
    rnd = P.rng(186)
    iron, orange = (52, 32, 22), (255, 140, 40)
    y0, L, w = 1.1, 4.6, 0.6
    edge, spine = K.katana_outline(y0, L, w, clip=0.56, tip="tanto", wf=lambda s: 1 + 0.32 * s,
                                   spine_pts=K.teeth(0.18, 0.5, 3, 0.06, lean=0.5))
    bl = Blade(sw, edge, spine, thick=0.13, bevel=0.15, kissaki=y0 + L - 0.7, bend=lambda s: 0.32 * s * s)
    d = bl.decal
    # molten blade: glowing orange edge, dark forged iron along the spine with rivets
    bl.paint_bevel((255, 196, 70))
    bl.paint_bevel((255, 240, 170), inset=0.62)
    d.fill([bl.band_poly(y0, y0 + L - 0.72, 0.64, 1.02)], (66, 42, 30))
    d.engrave([bl.pline(bl.line(0.64, y0 + 0.02, y0 + L - 0.74))], width=4, depth=200)
    for i in range(9):
        y = y0 + 0.2 + i * 0.4
        x, yy = bl.px(y, bl.flat(y, 0.84))
        d.emboss([[(x - 3, yy - 3), (x + 3, yy - 3), (x + 3, yy + 3), (x - 3, yy + 3)]], width=4, color=(120, 100, 90), closed=True)
    cr = []
    for i in range(7):
        y = y0 + 0.4 + i * 0.48
        z = bl.flat(y, 0.64)
        cr.append([(y, z), (y + 0.06, z - 0.05), (y + 0.1, z - 0.04), (y + 0.16, z - 0.1)])
    gl(bl, cr, (255, 230, 120), width=4, halo=8)
    bl.inlay(cr, width=0.018)
    runes = blade_runes(bl, rnd, y0 + 0.25, y0 + L - 0.95, 0.3, 7, 0.12, (255, 240, 140), width=0.026)
    bl.edge_glow()
    bl.finish((236, 106, 30), roughness=0.3)

    # horned iron guard: spiked bar, curling ram horns, gold rivets
    yc = 0.88
    half = [(0, 0.14), (0.3, 0.14), (0.42, 0.26), (0.48, 0.1), (0.66, 0.06), (0.5, -0.06), (0.56, -0.22), (0.36, -0.12), (0.16, -0.18), (0, -0.16)]
    g = sym(half)
    sw.plate(g, yc, 0.3, iron, bevel=0.02, paint=outline_paint(g, 0.78, color=(255, 160, 40), width=5))
    for side in (-1, 1):
        horn = [(0, yc + 0.06, side * 0.22), (0, yc + 0.32, side * 0.42), (0, yc + 0.38, side * 0.7), (0, yc + 0.2, side * 0.86),
                (0, yc + 0.0, side * 0.8), (0, yc + 0.02, side * 0.66), (0, yc + 0.14, side * 0.66)]
        sw.tube(horn, 0.1, (196, 170, 130), sides=8, taper=lambda t: 1 - 0.85 * t)
        for dy in (0.06, -0.08):
            sw.stud((0, yc + dy, side * 0.3), 0.03, 0.16, GOLD)
        sw.gem((0, yc + 0.06, side * 0.22), 0.06, 0.17, 4)
    sw.ring(yc, 0.12, 0.2, 0.36, iron, seg=12)
    sw.gem((0, yc, 0), 0.12, 0.21, 6)
    sw.box((0.24, 0.24, 0.7), (0, yc + 0.28, 0), iron, bevel=0.02, paint=engraved_block(spirals=0, key=True))
    sw.grip(-0.62, 0.66, 0.14, 0.18, (30, 10, 0), (255, 150, 40), style="straps", width=0.18)
    for y in (0.67, 0.02):
        sw.box((0.36, 0.12, 0.44), (0, y, 0), iron, bevel=0.02, paint=engraved_block(spirals=0, key=True))
    # pommel: spiked iron block with a molten gem
    sw.box((0.38, 0.28, 0.48), (0, -0.78, 0), iron, bevel=0.035, paint=engraved_block(spirals=0, rings=1, color=(255, 160, 40)))
    sw.gem((0, -0.78, 0), 0.09, 0.21, 6)
    for (a, ln) in ((-0.9, 0.18), (0.0, 0.22), (0.9, 0.18)):
        sw.spike((0, -0.92, math.sin(a) * 0.16), (0, -math.cos(a), math.sin(a)), ln, 0.06, iron)
    return sw.done()


def eventide():
    glow = (255, 170, 240)
    sw = Sword("eventide", glow, DECALS)
    rnd = P.rng(197)
    pink, plum, pale = (255, 196, 236), (110, 40, 130), (255, 228, 250)
    y0, L, w = 1.1, 4.8, 0.6
    edge, spine = K.katana_outline(y0, L, w, clip=0.74, tip="hook", hook=0.1, wf=lambda s: 1 + 0.08 * s)
    bl = Blade(sw, edge, spine, thick=0.12, bevel=0.14, kissaki=y0 + L - 0.94, bend=lambda s: 0.78 * s * s)
    d = bl.decal
    bl.paint_bevel((255, 230, 248))
    # twilight: violet spine band fading through pink to a white edge
    for k in range(8):
        f = 0.25 + k * 0.1
        d.fill([bl.band_poly(y0, y0 + L - 0.95, f, 1.02)], mix((246, 176, 220), (120, 60, 160), (k + 1) / 8), alpha=90)
    flowers = []
    for i, y in enumerate((y0 + 0.75, y0 + 1.6, y0 + 2.45, y0 + 3.2)):
        zc = bl.flat(y, 0.55 if i % 2 == 0 else 0.42)
        fl = []
        for k in range(5):
            a = k * 2 * math.pi / 5 + math.pi / 2
            fl.append([(y + math.sin(a) * 0.035, zc + math.cos(a) * 0.035), (y + math.sin(a - 0.4) * 0.1, zc + math.cos(a - 0.4) * 0.1),
                       (y + math.sin(a) * 0.12, zc + math.cos(a) * 0.12), (y + math.sin(a + 0.4) * 0.1, zc + math.cos(a + 0.4) * 0.1)])
        for p in fl:
            d.fill([bl.pline(p)], (255, 240, 252))
        flowers += fl
        for k in range(3):
            py_, pz = y + rnd.uniform(0.15, 0.35), bl.flat(y, rnd.uniform(0.1, 0.9))
            d.engrave([bl.pline(K.flame_poly(py_, pz, 0.07, 0.04) + [K.flame_poly(py_, pz, 0.07, 0.04)[0]])], width=2, depth=120)
    bl.slab(flowers)
    my, mz = y0 + 0.28, bl.flat(y0 + 0.28, 0.5)
    moon = crescent(0.1, 0.0, -0.12, -0.04, n=10)
    mp = [(my - dy, mz + z) for z, dy in moon]
    d.fill([bl.pline(mp)], (255, 250, 255))
    bl.slab([mp])
    vine = sinuous(bl, y0 + 0.5, y0 + L - 1.0, 0.5, 0.42, 4, phase=0.5)
    d.engrave([bl.pline(vine)], width=3, depth=120)
    bl.edge_glow()
    bl.finish((246, 178, 222), roughness=0.2)

    # pink feathered wings behind a sakura crest, falling petals
    yc = 0.96
    wings(sw, yc, [(0.16, 0.02, 40, 0.9, 0.22), (0.18, -0.02, 22, 0.84, 0.2), (0.18, -0.06, 4, 0.7, 0.18), (0.16, -0.1, -16, 0.52, 0.15)],
          pink, trim=(255, 255, 255), fill=(236, 110, 196), thick=0.2, glow_tips=True)
    sak = []
    for k in range(5):
        a = math.pi / 2 + k * 2 * math.pi / 5
        for da, r in ((-0.36, 0.3), (-0.12, 0.36), (0.0, 0.31), (0.12, 0.36), (0.36, 0.3), (0.62, 0.12)):
            sak.append((math.cos(a + da) * r, math.sin(a + da) * r))
    sw.plate(sak, yc, 0.3, plum, bevel=0.016, paint=outline_paint(sak, 0.82, color=(255, 220, 250), width=4))
    sw.setting((0, yc, 0), 0.15, 0.17, (255, 220, 250), segments=10)
    sw.gem((0, yc, 0), 0.12, 0.21, 10)
    for side in (-1, 1):
        for (z, dy, a, r) in ((0.9, 0.66, 0.6, 0.07), (0.66, 0.92, -0.4, 0.06), (1.06, 0.3, 1.2, 0.05)):
            pet = leaf(-r, 0, a, 2 * r, r * 1.1)
            sw.plate(pet, yc + dy, 0.06, None, glow=True, bevel=0.0, zc=side * z)
    sw.box((0.22, 0.22, 0.66), (0, yc + 0.34, 0), plum, bevel=0.02, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.6, 0.13, 0.17, (60, 20, 80), pale, style="ribbon", width=0.14)
    for y in (0.62, 0.0):
        sw.box((0.34, 0.12, 0.42), (0, y, 0), plum, bevel=0.02, paint=engraved_block(spirals=2))
    ps = [(x * 0.62, y * 0.62) for x, y in sak]
    sw.plate(ps, -0.86, 0.24, plum, bevel=0.015, paint=outline_paint(ps, 0.78, color=(255, 220, 250), width=4))
    sw.box((0.3, 0.16, 0.34), (0, -0.68, 0), plum, bevel=0.03)
    sw.gem((0, -0.86, 0), 0.08, 0.17, 10)
    sw.tassel((0, -1.06, 0), (255, 190, 236), length=0.5, lean=-0.15, cord_rgb=plum)
    return sw.done()


# ====================================================================== boss drops
def ancestral_blade():
    glow = (255, 210, 90)
    sw = Sword("ancestral_blade", glow, DECALS)
    rnd = P.rng(208)
    gold, bronze = (240, 186, 52), (110, 82, 36)
    y0, L, w = 1.08, 4.3, 0.56
    edge, spine = K.katana_outline(y0, L, w, clip=0.6, wf=lambda s: 1 + 0.05 * s)
    bl = Blade(sw, edge, spine, thick=0.11, bevel=0.13, kissaki=y0 + L - 0.8, bend=lambda s: 0.6 * s * s)
    d = bl.decal
    # cloud hamon: a frosty temper zone with a billowing line
    ys = bl.ys_between(y0, y0 + L - 0.8, 120)
    ham = [(y, bl.full(y, 0.36 + 0.06 * math.sin((y - y0) * 9) + 0.03 * math.sin((y - y0) * 23))) for y in ys]
    poly = [bl.px(y, bl.at(y, "ze") - 0.03) for y in ys] + [bl.px(y, z) for y, z in reversed(ham)]
    d.fill([poly], (242, 238, 224), alpha=230, blur=2)
    d.engrave([bl.pline(ham)], width=2, depth=90)
    # bronze cartouche of glowing ancestral glyphs, cloud scrolls up the spine
    ca, cb = y0 + 0.15, y0 + 1.55
    cp = bl.band_poly(ca, cb, 0.48, 0.94)
    d.fill([cp], bronze)
    d.emboss([cp + [cp[0]]], width=5, color=GOLD, closed=True)
    glyphs = []
    for i in range(5):
        y = ca + 0.17 + i * 0.26
        glyphs += K.rune_strokes(y, bl.flat(y, 0.71), 0.11, rnd)
    gl(bl, glyphs, glow, width=5, halo=9)
    bl.inlay(glyphs, width=0.026)
    for i in range(5):
        y = cb + 0.25 + i * 0.36
        d.engrave([P.spiral(*bl.px(y, bl.flat(y, 0.78)), 12, 2, 1.3, cw=1 if i % 2 else -1)], width=3, depth=150)
    spl = bl.line(0.93, cb + 0.1, y0 + L - 1.0)
    gl(bl, [spl], glow, width=4, halo=8)
    bl.inlay([spl], width=0.018)
    studs = [K.diamond_poly(y, bl.flat(y, 0.78), 0.07, 0.04) for y in (cb + 0.4, cb + 1.0, cb + 1.6)]
    for st in studs:
        bl.decal.fill([bl.pline(st)], (255, 236, 160))
    bl.slab(studs)
    bl.edge_glow()
    bl.finish((214, 204, 176), roughness=0.3)

    # chrysanthemum guard (16 petals) in old gold
    yc = 0.9
    flower = circ_out(0.56, 96, fn=lambda a: 0.52 + 0.06 * abs(math.cos(8 * a)) ** 0.5)

    def petals(dd, gx, gy):
        dd.fill([[(gx(z), gy(dy)) for z, dy in circ_out(0.36, 40)]], (160, 108, 30))
        for k in range(16):
            a = (k + 0.5) * math.pi / 8
            dd.engrave([[(gx(math.cos(a) * 0.36), gy(math.sin(a) * 0.36)), (gx(math.cos(a) * 0.52), gy(math.sin(a) * 0.52))]], width=4, depth=160)
        dd.emboss([[(gx(z), gy(dy)) for z, dy in circ_out(0.36, 40)]], width=6, color=(255, 226, 140), closed=True)
    sw.plate(flower, yc, 0.24, gold, bevel=0.016, roughness=0.3, paint=petals)
    sw.plate(circ_out(0.24, 16, fn=lambda a: 0.22 + 0.035 * abs(math.cos(4 * a))), yc, 0.32, gold, bevel=0.016, roughness=0.3)
    sw.gem((0, yc, 0), 0.13, 0.2, 8)
    for k in range(8):
        a = (k + 0.5) * math.pi / 4
        sw.stud((0, yc + math.sin(a) * 0.24, math.cos(a) * 0.24), 0.025, 0.15, (255, 226, 140))
    sw.box((0.22, 0.22, 0.62), (0, yc + 0.34, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.5, 0.13, 0.17, (40, 30, 20), (224, 182, 92), style="straps", width=0.17)
    sw.box((0.34, 0.12, 0.42), (0, 0.0, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    sw.box((0.36, 0.24, 0.46), (0, -0.76, 0), gold, bevel=0.035, roughness=0.3, paint=engraved_block(spirals=4))
    sw.gem((0, -0.76, 0), 0.07, 0.2, 8)
    sw.tassel((0, -0.88, 0), (200, 150, 60), length=0.66, lean=-0.2, cord_rgb=(120, 80, 30))
    return sw.done()


def hellfang():
    glow = (255, 60, 0)
    sw = Sword("hellfang", glow, DECALS)
    rnd = P.rng(219)
    char, blood = (54, 20, 16), (90, 8, 4)
    y0, L, w = 1.1, 4.5, 0.62
    fangs = K.teeth(0.24, 0.78, 3, 0.15, lean=0.86)
    edge, spine = K.katana_outline(y0, L, w, clip=0.72, tip="hook", hook=0.12, wf=lambda s: 1 + 0.06 * s, spine_pts=fangs,
                                   edge_pts=K.teeth(0.04, 0.26, 5, 0.04, lean=0.3))
    bl = Blade(sw, edge, spine, thick=0.13, bevel=0.15, kissaki=y0 + L - 0.92, bend=lambda s: 0.85 * s * s)
    d = bl.decal
    bl.paint_bevel((206, 60, 10))
    bl.paint_bevel((255, 160, 50), inset=0.6)
    # lava cracks spidering across charred steel
    cracks = []
    for (ya, yb, f) in ((y0 + 0.1, y0 + 1.3, 0.5), (y0 + 1.1, y0 + 2.3, 0.4), (y0 + 2.1, y0 + 3.4, 0.5)):
        cracks += K.crack(rnd, ya, yb, lambda y, f=f: bl.flat(y, f), 0.08, n=8, branches=4, blen=0.45)
    d.glow([bl.pline(c) for c in cracks], (255, 110, 20), width=9, halo=16)
    d.glow([bl.pline(c) for c in cracks], (255, 210, 120), width=3, halo=2)
    bl.inlay(cracks, width=0.03)
    for i in range(30):
        y = y0 + rnd.uniform(0.1, L - 1.0)
        x, yy = bl.px(y, bl.flat(y, rnd.uniform(0, 1)))
        d.fill([[(x - 4, yy), (x, yy - 4), (x + 4, yy), (x, yy + 4)]], (30, 10, 8), alpha=160, blur=1.2)
    bl.edge_glow()
    bl.finish((58, 22, 18), roughness=0.4)

    # demon-mask guard: horns, slit eyes, fangs
    yc = 0.88
    half = [(0, 0.22), (0.14, 0.24), (0.28, 0.54), (0.34, 0.2), (0.5, 0.14), (0.7, 0.4), (0.62, 0.02), (0.46, -0.12),
            (0.32, -0.32), (0.24, -0.14), (0.12, -0.36), (0.05, -0.16), (0, -0.18)]
    g = sym(half)
    sw.plate(g, yc, 0.3, blood, bevel=0.018, paint=outline_paint(g, 0.76, color=(255, 120, 30), width=5,
                                                                    spirals=((0.4, 0.0, 10, 1), (-0.4, 0.0, 10, -1))))
    for side in (-1, 1):
        eye = [(side * 0.12, 0.06), (side * 0.3, 0.12), (side * 0.32, 0.06), (side * 0.16, 0.02)]
        if side < 0:
            eye = list(reversed(eye))
        sw.plate(eye, yc, 0.34, None, glow=True, bevel=0.0)
        sw.spike((0, yc + 0.46, side * 0.27), (0, 1, side * 0.1), 0.14, 0.035, (40, 0, 0))
        sw.spike((0, yc + 0.34, side * 0.66), (0, 1, side * 0.4), 0.14, 0.035, (40, 0, 0))
        for (z, dy) in ((0.3, -0.28), (0.12, -0.32)):
            sw.spike((0, yc + dy, side * z), (0, -1, 0), 0.1, 0.03, (240, 226, 200))
    sw.gem((0, yc - 0.1, 0), 0.07, 0.18, 4, roll=0.0)
    sw.box((0.24, 0.24, 0.7), (0, yc + 0.3, 0), (40, 0, 0), bevel=0.02, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.66, 0.14, 0.18, (20, 0, 0), (255, 90, 20), style="straps", width=0.18)
    sw.box((0.36, 0.12, 0.44), (0, 0.67, 0), (40, 0, 0), bevel=0.02)
    sw.box((0.38, 0.26, 0.48), (0, -0.78, 0), blood, bevel=0.035, paint=engraved_block(spirals=0, rings=1, color=(255, 120, 30)))
    sw.gem((0, -0.78, 0), 0.09, 0.21, 6)
    for (a, ln) in ((-1.0, 0.2), (-0.35, 0.16), (0.35, 0.16), (1.0, 0.2)):
        sw.spike((0, -0.9, math.sin(a) * 0.18), (0, -math.cos(a), math.sin(a)), ln, 0.05, (40, 0, 0))
    return sw.done()


def masters_whisper():
    glow = (200, 150, 255)
    sw = Sword("masters_whisper", glow, DECALS)
    rnd = P.rng(231)
    dusk, lilac = (44, 22, 66), (200, 150, 255)
    y0, L, w = 1.04, 4.6, 0.46
    edge, spine = K.katana_outline(y0, L, w, clip=0.8, wf=lambda s: 1 - 0.12 * s)
    bl = Blade(sw, edge, spine, thick=0.1, bevel=0.11, kissaki=y0 + L - 1.0, bend=lambda s: 0.78 * s * s)
    d = bl.decal
    bl.paint_bevel((198, 176, 236))
    bl.paint_bevel((240, 228, 255), inset=0.62)
    ya, yb = y0 + 0.1, y0 + L - 1.08
    channel(bl, ya, yb, 0.08, 0.94, (70, 50, 100), depth=120)
    winds = [sinuous(bl, ya + 0.08, yb - 0.04, 0.5, 0.3, 3.5, phase=0.0), sinuous(bl, ya + 0.08, yb - 0.04, 0.5, 0.3, 3.5, phase=math.pi)]
    gl(bl, winds, lilac, width=5, halo=12)
    bl.inlay(winds, width=0.02)
    for i in range(7):
        y = ya + 0.25 + i * (yb - ya - 0.4) / 6
        f = 0.5 + 0.3 * math.sin(i * 2.2)
        d.engrave([P.spiral(*bl.px(y, bl.flat(y, f)), 10, 2, 1.4, cw=1 if i % 2 else -1)], width=2, depth=60, light=170)
    bl.edge_glow(out=0.01, inn=0.035)
    bl.finish((112, 92, 148), roughness=0.2)

    # inverted crescent guard (horns to the grip) over a glowing inner moon
    yc = 0.9
    cres = crescent(0.84, 0.4, -0.18, 0.2, n=16, up=False)
    mid = [(0.76 * math.cos(math.pi + math.pi * i / 14), -(0.38 - 0.48 * math.sin(math.pi * i / 14))) for i in range(15)]
    sw.plate(cres, yc, 0.24, dusk, bevel=0.018, paint=lambda dd, gx, gy: (
        dd.emboss([[(gx(z), gy(dy)) for z, dy in mid]], width=6, color=lilac),
        [dd.engrave([P.spiral(gx(s * 0.5), gy(0.02), 12, 3, 1.3, cw=s)], width=3, depth=140) for s in (-1, 1)]))
    inner = crescent(0.5, 0.14, -0.08, 0.04, n=12)
    sw.plate([(z, dy + 0.16) for z, dy in inner], yc, 0.28, None, glow=True, bevel=0.0)
    for side in (-1, 1):
        sw.crystal((0, yc - 0.34, side * 0.8), (0, -1, side * 0.3), 0.2, 0.045)
        sw.crystal((0, yc + 0.28, side * 0.5), (0, 1, side * 0.5), 0.12, 0.03)
        sw.stud((0, yc + 0.02, side * 0.36), 0.03, 0.13, (180, 160, 210))
    sw.setting((0, yc + 0.02, 0), 0.11, 0.15, (180, 160, 210), segments=6)
    sw.gem((0, yc + 0.02, 0), 0.09, 0.18, 6)
    sw.box((0.18, 0.2, 0.5), (0, yc + 0.24, 0), dusk, bevel=0.02, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.66, 0.12, 0.16, (12, 6, 22), lilac, style="ribbon", width=0.13)
    sw.box((0.3, 0.1, 0.38), (0, 0.67, 0), dusk, bevel=0.02)
    # ring pommel with a glowing inner ring and a silk cord
    sw.box((0.3, 0.14, 0.36), (0, -0.7, 0), dusk, bevel=0.03)
    sw.ring(-0.97, 0.13, 0.22, 0.18, dusk, seg=24, paint=lambda dd, gx, gy: dd.emboss([[(gx(0.175 * math.cos(a)), gy(0.175 * math.sin(a))) for a in [k * math.pi / 20 for k in range(41)]]], width=4, color=lilac))
    sw.ring(-0.97, 0.1, 0.135, 0.1, glow=True, seg=24)
    sw.tube([(0, -1.16, 0), (0, -1.3, -0.06), (0, -1.46, -0.04), (0, -1.58, -0.12)], 0.025, lilac, sides=6, taper=lambda t: 1 - 0.5 * t)
    return sw.done()


def emperors_end():
    glow = (255, 100, 255)
    sw = Sword("emperors_end", glow, DECALS)
    rnd = P.rng(242)
    royal, gold, pearl = (74, 20, 110), (246, 194, 62), (242, 240, 250)
    y0, L, w = 1.14, 5.2, 0.66
    crown = K.teeth(0.06, 0.32, 5, 0.05, lean=0.5)
    edge, spine = K.katana_outline(y0, L, w, clip=0.78, wf=lambda s: 1 + 0.1 * s, spine_pts=crown)
    bl = Blade(sw, edge, spine, thick=0.13, bevel=0.15, kissaki=y0 + L - 1.0, bend=lambda s: 0.75 * s * s)
    d = bl.decal
    bl.paint_bevel((206, 150, 250))
    bl.paint_bevel((252, 226, 255), inset=0.62)
    ya, yb = y0 + 0.75, y0 + L - 1.12
    fl = []
    for fa, fb in ((0.1, 0.32), (0.62, 0.84)):
        channel(bl, ya, yb, fa, fb, (58, 8, 90))
        fl.append(bl.line((fa + fb) / 2, ya + 0.08, yb - 0.08))
    gl(bl, fl, glow, width=6, halo=12)
    bl.inlay(fl, width=0.032)
    # gold vine between the fullers, glowing runes in the middle
    vine = sinuous(bl, ya, yb, 0.47, 0.06, 7)
    d.emboss([bl.pline(vine)], width=4, color=GOLD)
    for i in range(14):
        y, z = vine[i * 4 + 2]
        d.emboss([P.spiral(*bl.px(y, z), 9, 2, 1.2, cw=1 if i % 2 else -1)], width=3, color=GOLD)
    # imperial crest at the base
    cy, cz = y0 + 0.36, bl.flat(y0 + 0.36, 0.5)
    crest = [(cy + 0.24, cz), (cy + 0.1, cz + 0.17), (cy - 0.14, cz + 0.13), (cy - 0.26, cz), (cy - 0.14, cz - 0.13), (cy + 0.1, cz - 0.17)]
    d.fill([bl.pline(crest)], (58, 8, 90))
    d.emboss([bl.pline(crest + [crest[0]])], width=5, color=GOLD)
    gemc = K.diamond_poly(cy, cz, 0.13, 0.08)
    d.fill([bl.pline(gemc)], (255, 160, 255))
    bl.slab([gemc], raise_=0.018)
    bl.edge_glow()
    bl.finish((240, 238, 248), roughness=0.25)

    # imperial wings: royal purple feathers, gold trim, crest shield, gems, floating shards
    yc = 0.98
    wings(sw, yc, [(0.2, 0.04, 44, 1.0, 0.24), (0.22, 0.0, 26, 0.98, 0.22), (0.22, -0.04, 8, 0.86, 0.2), (0.2, -0.08, -10, 0.68, 0.18), (0.18, -0.12, -28, 0.48, 0.15)],
          royal, trim=gold, fill=(124, 52, 176), thick=0.22, glow_tips=True)
    shield = [(0, 0.38), (0.2, 0.3), (0.3, 0.1), (0.24, -0.16), (0, -0.32), (-0.24, -0.16), (-0.3, 0.1), (-0.2, 0.3)]
    sw.plate(shield, yc, 0.32, gold, bevel=0.02, roughness=0.3, paint=outline_paint(shield, 0.78, color=(255, 236, 170), width=5, fill=royal))
    sw.setting((0, yc + 0.02, 0), 0.16, 0.18, gold, segments=8)
    sw.gem((0, yc + 0.02, 0), 0.14, 0.22, 8)
    for side in (-1, 1):
        sw.gem((0, yc + 0.18, side * 0.14), 0.04, 0.17, 4, roll=0.0)
        for (z, dy, ln) in ((1.02, 0.94, 0.2), (1.2, 0.5, 0.16), (0.74, 1.12, 0.14)):
            sw.crystal((0, yc + dy - ln / 2, side * z), (0, 1, side * 0.15), ln, 0.05, sides=4, foot=0.2, tip=0.5)
    sw.box((0.24, 0.24, 0.74), (0, yc + 0.36, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    sw.grip(-0.62, 0.6, 0.14, 0.18, (24, 0, 36), (255, 255, 255), style="straps", width=0.18)
    for y in (0.62, 0.0):
        sw.box((0.36, 0.12, 0.44), (0, y, 0), gold, bevel=0.02, roughness=0.3, paint=engraved_block(spirals=2))
    # crown pommel
    cr = [(-0.26, 0.12), (-0.26, -0.14), (0.26, -0.14), (0.26, 0.12), (0.2, 0.0), (0.13, 0.16), (0.06, 0.0), (0.0, 0.2), (-0.06, 0.0), (-0.13, 0.16), (-0.2, 0.0)]
    cr = [(z, -dy) for z, dy in reversed(cr)]
    sw.plate(cr, -0.86, 0.3, gold, bevel=0.016, roughness=0.3, paint=outline_paint(cr, 0.8, color=(255, 236, 170), width=4, fill=royal))
    sw.box((0.3, 0.14, 0.36), (0, -0.68, 0), gold, bevel=0.03, roughness=0.3)
    sw.gem((0, -0.84, 0), 0.08, 0.2, 8)
    for z in (-0.26, 0.0, 0.26):
        sw.gem((0, -1.04 - (0.04 if z == 0 else 0), z), 0.035, 0.17, 4, roll=0.0)
    return sw.done()


BUILD = {
    "amethyst_katana": amethyst_katana,
    "ember_katana": ember_katana,
    "obsidian_katana": obsidian_katana,
    "frostmoon_katana": frostmoon_katana,
    "sunforged_katana": sunforged_katana,
    "bloodmoon_katana": bloodmoon_katana,
    "umbra_katana": umbra_katana,
    "starfall_katana": starfall_katana,
    "oblivion_katana": oblivion_katana,
    "oak_fang": oak_fang,
    "viper_edge": viper_edge,
    "stormcaller": stormcaller,
    "demonbane": demonbane,
    "nightglass": nightglass,
    "ragnablade": ragnablade,
    "eventide": eventide,
    "ancestral_blade": ancestral_blade,
    "hellfang": hellfang,
    "masters_whisper": masters_whisper,
    "emperors_end": emperors_end,
}
SIZES = {}
