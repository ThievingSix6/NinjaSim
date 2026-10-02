"""Hero katanas: brown, jade and tide modelled after justin's reference sheets, plus every
other katana in Katanas.lua designed from its Look colours (hero_katana_designs.py, built
from the parts in hero_katana_kit.py).

Each katana is ONE textured mesh "HeroKatana_<id>" (plus "HeroKatana_<id>__Glow" for
neon runes/gems), baked into assets/textures/HeroKatana_<id>.png and embedded in
the FBX. Frame: the middle of the grip is the origin, the blade runs along Blender
+Y (Roblox -Z), width along Blender Z with the cutting edge at -Z, flat faces +-X.

Run: python3 tools/blender/hero_katanas.py <out_dir> [ids...]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402,F401  (loads mathutils)
from mathutils import Vector  # noqa: E402

import bake  # noqa: E402
import common as C  # noqa: E402
import hero as H  # noqa: E402
import hero_katana_designs as D  # noqa: E402
import hero_katana_kit as K  # noqa: E402
import patterns as P  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/hero_katanas"
ONLY = sys.argv[2:]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# HERO_TEX / HERO_PREV redirect textures and previews (scratch renders while iterating)
TEX = os.environ.get("HERO_TEX") or os.path.join(ROOT, "assets", "textures")
PREV = os.environ.get("HERO_PREV") or os.path.join(ROOT, "assets", "previews", "hero")
for d in (OUT, TEX, PREV):
    os.makedirs(d, exist_ok=True)

# id -> blade base / tip in the model frame (Blender coords), written to the manifest notes
INFO = {}
DECALS = os.path.join(OUT, "decals")
os.makedirs(DECALS, exist_ok=True)


def decal_file(name, decal):
    return decal.save(os.path.join(DECALS, name + ".png"))


def box_decal(name, size, center, color, image, bevel=0.02, facing=(1, 0, 0), axes=(2, 1), **kw):
    """Bevelled box with a decal on its +-X faces (u along Z, v along Y by default)."""
    mat = H.decal_paint(name + "Mat", color, image, facing=facing, **kw)
    o = C.box(name, size, center, mat, bevel=bevel)
    return H.planar_decal_uv(o, *axes)


def tapered_core(name, y0, y1, bottom, top, mat):
    """Rectangular grip core from (x, z) half sizes `bottom` at y0 to `top` at y1."""
    v = []
    for (hx, hz), y in ((bottom, y0), (top, y1)):
        v += [(hx, y, hz), (-hx, y, hz), (-hx, y, -hz), (hx, y, -hz)]
    return H.flat(name, v, C.loft([[0, 1, 2, 3], [4, 5, 6, 7]]), mat)


# ---------------------------------------------------------------- brown katana
def brown_katana():
    steel = H.paint("BrownSteel", (206, 207, 211), roughness=0.35)
    leather = H.paint("BrownLeather", (124, 80, 46), noise=0.10, scale=60)
    core = H.paint("BrownCore", (92, 58, 33), noise=0.08, scale=60)
    wood = H.paint("BrownBox", (128, 84, 50), noise=0.06, scale=40)
    parts = []

    # blade: 12 studded "pyramid" cells and a chisel tip
    t, w, h = 0.085, 0.29, 0.05
    y = 0.74
    cell = 0.255
    for i in range(12):
        y0, y1 = y + i * cell + 0.003, y + (i + 1) * cell - 0.003
        ym = (y0 + y1) / 2
        v = [(-t / 2, y0, -w / 2), (-t / 2, y0, w / 2), (-t / 2, y1, w / 2), (-t / 2, y1, -w / 2),
             (t / 2, y0, -w / 2), (t / 2, y0, w / 2), (t / 2, y1, w / 2), (t / 2, y1, -w / 2),
             (t / 2 + h, ym, 0), (-t / 2 - h, ym, 0)]
        f = [(4, 5, 8), (5, 6, 8), (6, 7, 8), (7, 4, 8),          # front pyramid
             (1, 0, 9), (2, 1, 9), (3, 2, 9), (0, 3, 9),          # back pyramid
             (0, 4, 7, 3), (1, 2, 6, 5), (0, 1, 5, 4), (3, 7, 6, 2)]
        parts.append(H.flat("BCell%d" % i, v, f, steel))
    yc = y + 12 * cell
    # chisel tip: straight block up to a slanted line, then a bevel down to a thin ridge
    lo_e, lo_s = yc + 0.08, yc + 0.34      # bevel starts (edge side, spine side)
    hi_e, hi_s = yc + 0.34, yc + 0.62      # ridge / point
    rt = 0.012
    v = [(-t / 2, yc, -w / 2), (-t / 2, yc, w / 2), (t / 2, yc, w / 2), (t / 2, yc, -w / 2),
         (-t / 2, lo_e, -w / 2), (-t / 2, lo_s, w / 2), (t / 2, lo_s, w / 2), (t / 2, lo_e, -w / 2),
         (-rt, hi_e, -w / 2), (-rt, hi_s, w / 2), (rt, hi_s, w / 2), (rt, hi_e, -w / 2)]
    f = C.loft([[0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11]])
    parts.append(H.flat("BTip", v, f, steel))
    tip = Vector((0, hi_s, w / 2))

    # guard: hollow box the blade sits in
    parts.append(H.tray("BGuard", (0.36, 0.22, 0.54), (0, 0.66, 0), wood, rim=0.04, depth=0.07))
    # grip core + criss-cross leather straps
    parts.append(C.box("BCore", (0.2, 1.16, 0.27), (0, -0.02, 0), core))
    for hand, phase in ((1, 0.0), (-1, 0.5)):
        parts.append(H.rect_band("BStrap%d" % hand, 0.1, 0.135, -0.49, 3.3, 0.3, 0.19, 0.036, leather, phase=phase, hand=hand, gap=0.002 if hand > 0 else 0.03))
    # pommel cup
    parts.append(H.tray("BPommel", (0.33, 0.3, 0.37), (0, -0.7, 0), wood, rim=0.035, depth=0.06))
    INFO["brown_katana"] = (Vector((0, 0.74, 0)), tip)
    return parts, [], 1


# ---------------------------------------------------------------- jade katana (green)
def jade_katana():
    green = (44, 186, 60)
    wrapc = (58, 204, 72)
    coreg = (22, 104, 32)
    steel = (204, 206, 210)
    r = P.rng(7)
    parts = []

    # blade engraving: fuller lines, greek keys, diamonds, stepped temper line
    W, Hh = 320, 2048
    d = P.Decal(W, Hh)

    def py(v):
        return (1 - v) * Hh
    d.engrave([[(0.74 * W, py(0.08)), (0.74 * W, py(0.86)), (0.8 * W, py(0.93))],
               [(0.84 * W, py(0.08)), (0.84 * W, py(0.88)), (0.9 * W, py(0.95))]], width=5, depth=190)
    for v0, n in ((0.875, 1), (0.43, 3), (0.02, 1)):
        for i in range(n):
            y = py(v0 + (i + 1) * 0.034)
            d.fill([[(0.64 * W, y), (0.95 * W, y), (0.95 * W, y + 0.034 * Hh), (0.64 * W, y + 0.034 * Hh)]], steel, alpha=255, blur=0)
            d.engrave(P.meander_block(0.66 * W, y + 4, 0.27 * W, 0.034 * Hh - 8), width=4, depth=190)
    for v in (0.22, 0.39, 0.56):
        d.engrave(P.diamond(0.42 * W, py(v), 0.07 * W, 0.034 * Hh), width=5, depth=190)
    d.engrave(P.stepped_line(0.3 * W, py(0.86), py(0.05), 0.05 * W, 0.035 * Hh, r), width=5, depth=190)
    blade_img = decal_file("jade_blade", d)
    bmat = H.decal_paint("JadeSteel", steel, blade_img, roughness=0.35)
    parts.append(H.blade("JBlade", bmat, 1.0, 3.6, 0.5, thick=0.1, bevel=0.12, clip=0.46, chisel=0.14,
                         curve=0.3, width_fn=lambda s: 1 + 0.08 * s))

    # habaki (collar) with a greek-key frieze
    d = P.Decal(256, 96)
    d.engrave(P.meander_band(10, 18, 240, 60), width=4)
    parts.append(box_decal("JCollar", (0.2, 0.24, 0.5), (0, 1.05, 0.0), steel, decal_file("jade_collar", d), bevel=0.012, roughness=0.35))

    # guard: bar plus two stacked greek-key blocks on each end
    d = P.Decal(128, 128)
    d.engrave(P.meander_block(14, 14, 100, 100), width=6, depth=170, light=90)
    cap = decal_file("jade_cap", d)
    parts.append(C.box("JGuardBar", (0.36, 0.2, 0.62), (0, 0.84, 0), H.paint("JadeBar", green, noise=0.04), bevel=0.02))
    for zs in (-1, 1):
        for i, yc in enumerate((0.72, 0.97)):
            parts.append(box_decal("JCap%d%d" % (zs, i), (0.42, 0.24, 0.24), (0, yc, zs * 0.42), green, cap, bevel=0.035, noise=0.04))

    # grip: dark core with two opposing wide straps (diamond tsuka-ito)
    core = H.paint("JadeCore", coreg, noise=0.05)
    strap = H.paint("JadeStrap", wrapc, noise=0.05)
    parts.append(tapered_core("JCore", -0.66, 0.76, (0.16, 0.235), (0.15, 0.215), core))
    for hand, phase in ((1, 0.0), (-1, 0.5)):
        parts.append(H.rect_band("JStrap%d" % hand, 0.155, 0.225, -0.6, 3.9, 0.34, 0.2, 0.03, strap, phase=phase, hand=hand,
                                 gap=0.002 if hand > 0 else 0.028))

    # pommel: neck + wide base with a greek-key face
    parts.append(C.box("JPommelNeck", (0.4, 0.18, 0.56), (0, -0.74, 0), H.paint("JadeNeck", green, noise=0.04), bevel=0.03))
    d = P.Decal(192, 96)
    d.engrave(P.meander_block(40, 12, 112, 72), width=5, depth=170, light=90)
    parts.append(box_decal("JPommel", (0.46, 0.24, 0.7), (0, -0.94, 0), green, decal_file("jade_pommel", d), bevel=0.045, noise=0.04))
    tip = Vector((0, 1.0 + 3.6, 0.27 + 0.3))
    INFO["jade_katana"] = (Vector((0, 1.0, 0)), tip)
    return parts, [], 25


# ---------------------------------------------------------------- tide katana (blue)
GLOW_BLUE = (30, 205, 255)
GOLD = (240, 186, 52)


def gem(name, x_half, r, center, segments, mat, dome=0.35):
    """Faceted gem through a part (visible on both flat faces), axis along X."""
    prof = [(0.001, -x_half - r * dome), (r * 0.62, -x_half), (r, -x_half * 0.6), (r, x_half * 0.6), (r * 0.62, x_half), (0.001, x_half + r * dome)]
    o = C.lathe(name, prof, segments, mat, axis="X", smooth=False)
    o.location = center
    o.rotation_euler = (math.pi / segments if segments == 6 else math.pi / 4, 0, 0)
    C.apply_transforms([o])
    return o


def tide_katana():
    steel = (206, 208, 214)
    blue = (34, 146, 226)
    deep = (18, 86, 160)
    r = P.rng(11)
    parts, glow = [], []

    # blade: faceted dao, darker engraved channel with glowing knots on the spine side,
    # small glowing runes along the edge side, filigree borders
    W, Hh = 320, 2048

    def py(v):
        return (1 - v) * Hh
    d = P.Decal(W, Hh)
    d.fill([[(0.5 * W, py(0.03)), (0.93 * W, py(0.03)), (0.93 * W, py(0.9)), (0.5 * W, py(0.86))]], (128, 134, 148), blur=1)
    d.engrave([[(0.5 * W, py(0.03)), (0.93 * W, py(0.03)), (0.93 * W, py(0.9)), (0.5 * W, py(0.86)), (0.5 * W, py(0.03))]], width=4, depth=200)
    d.engrave(P.scroll_vine(0.965 * W, py(0.92), py(0.04), 5, 150), width=3, depth=170)
    for v in (0.05, 0.84):
        for side in (-1, 1):
            d.engrave([P.spiral(0.715 * W + side * 30, py(v), 16, 3, 1.2, cw=side)], width=3, depth=180)
    for i, v in enumerate((0.14, 0.27, 0.4)):
        d.glow(P.knot(0.715 * W, py(v), 70), GLOW_BLUE, width=6, halo=9)
        d.glow(P.rune(0.715 * W, py(v + 0.065), 52, r), GLOW_BLUE, width=6, halo=9)
    for k in range(3):
        v = 0.5 + k * 0.12
        d.glow([P.spiral(0.715 * W - 18, py(v), 30, 4, 1.4, a0=0), P.spiral(0.715 * W + 18, py(v + 0.05), 30, 4, 1.4, a0=math.pi, cw=-1)], GLOW_BLUE, width=5, halo=8)
    d.glow([[(0.715 * W - 18 + 30, py(v)), (0.715 * W + 18 - 30, py(v + 0.05))] for v in (0.5, 0.62, 0.74)], GLOW_BLUE, width=5, halo=8)
    for v in (0.1, 0.25, 0.4, 0.55, 0.7):
        d.glow(P.rune(0.28 * W, py(v), 46, r), GLOW_BLUE, width=6, halo=8)
    bmat = H.decal_paint("TideSteel", steel, decal_file("tide_blade", d), roughness=0.35)
    parts.append(H.blade("TBlade", bmat, 1.08, 3.8, 0.5, thick=0.11, bevel=0.12, clip=0.55, chisel=0.2,
                         stations=6, bend_fn=lambda s: 0.5 * s * s, width_fn=lambda s: 1 + 0.24 * s))

    # guard: blue bow-tie with gold filigree, hex gem in the middle, small gems and gold studs
    yc = 0.98
    tie = [(-0.62, -0.22), (-0.62, 0.26), (-0.2, 0.15), (0.2, 0.15), (0.62, 0.26), (0.62, -0.22), (0.2, -0.13), (-0.2, -0.13)]
    GW, GH = 640, 248

    def gx(z):
        return (z + 0.62) / 1.24 * GW

    def gy(dy):
        return (0.26 - dy) / 0.48 * GH
    d = P.Decal(GW, GH)
    inset = [(z * 0.93, dy * 0.8 + 0.02) for z, dy in tie]
    d.emboss([[(gx(z), gy(dy)) for z, dy in inset]], width=9, color=GOLD, closed=True)
    for side in (-1, 1):
        cz = side * 0.42
        d.emboss([[(gx(cz), gy(0.2)), (gx(cz + 0.13), gy(0.03)), (gx(cz), gy(-0.14)), (gx(cz - 0.13), gy(0.03))]], width=7, color=GOLD, closed=True)
        d.engrave([P.spiral(gx(side * 0.27), gy(0.02), 16, 3, 1.3, cw=side)], width=3, depth=140)
    star = []
    for k in range(16):
        a = k * math.pi / 8
        rr = 0.2 if k % 2 == 0 else 0.11
        star.append((gx(math.cos(a) * rr * 1.1), gy(0.02 + math.sin(a) * rr * 0.9)))
    gmat = H.decal_paint("TideGuard", blue, decal_file("tide_guard", d), noise=0.04)
    guard = C.extrude_outline("TGuard", [(yc + dy, z) for z, dy in tie], 0.26, gmat, axis="X", bevel=0.025)
    parts.append(H.planar_decal_uv(guard, 2, 1))
    gold = H.paint("TideGold", GOLD, noise=0.05, roughness=0.3)
    d = P.Decal(256, 256)
    star = []
    for k in range(16):
        a = k * math.pi / 8 + math.pi / 16
        rr = 118 if k % 2 == 0 else 70
        star.append((128 + math.cos(a) * rr, 128 + math.sin(a) * rr))
    d.fill([star], GOLD)
    d.emboss([star], width=5, closed=True)
    d.engrave([P.spiral(128 + math.cos(a) * 80, 128 + math.sin(a) * 80, 14, 3, 1.2) for a in (0.4, 2.0, 3.5, 5.1)], width=3, depth=150)
    parts.append(box_decal("TGuardCore", (0.32, 0.42, 0.4), (0, yc + 0.02, 0), blue, decal_file("tide_core", d), bevel=0.03, noise=0.04))
    for side in (-1, 1):
        for dz, dy in ((0.56, 0.2), (0.56, -0.16), (0.24, 0.12), (0.24, -0.1)):
            parts.append(gem("TStud%d%d" % (side, int(dz * 100 + dy * 10)), 0.14, 0.045, (0, yc + dy, side * dz), 4, gold, dome=1.2))
    gm = H.paint("TideGem", GLOW_BLUE, roughness=0.1, emission=1.5, roblox="Neon")
    glow.append(gem("TGemMain", 0.2, 0.15, (0, yc + 0.02, 0), 6, gm, dome=0.6))
    for side in (-1, 1):
        glow.append(gem("TGemSide%d" % side, 0.16, 0.075, (0, yc + 0.03, side * 0.42), 4, gm, dome=0.7))
        parts.append(gem("TSetting%d" % side, 0.145, 0.11, (0, yc + 0.03, side * 0.42), 4, gold, dome=0.05))

    # gold collar under the guard, ribbon-wrapped grip with a gold band, gem pommel with claws
    d = P.Decal(160, 96)
    d.engrave(P.rect(8, 8, 152, 88), width=4, depth=150)
    for side in (-1, 1):
        d.engrave([P.spiral(80 + side * 34, 48, 22, 3, 1.3, cw=side)], width=3, depth=160)
    band = decal_file("tide_band", d)
    parts.append(box_decal("TCollar", (0.3, 0.24, 0.38), (0, 0.72, 0), GOLD, band, bevel=0.025, roughness=0.3))
    core = H.paint("TideCore", deep, noise=0.05)
    ribbon = H.paint("TideRibbon", (40, 152, 232), noise=0.06)
    parts.append(tapered_core("TCore", -0.62, 0.62, (0.13, 0.17), (0.13, 0.17), core))
    for hand, phase, gap in ((1, 0.0, 0.003), (-1, 0.35, 0.02)):
        parts.append(H.rect_band("TRib%d" % hand, 0.13, 0.17, -0.58, 7.6 if hand > 0 else 4.0, 0.15 if hand > 0 else 0.29,
                                 0.14, 0.018, ribbon, phase=phase, hand=hand, gap=gap))
    parts.append(box_decal("TBand", (0.34, 0.14, 0.42), (0, -0.02, 0), GOLD, band, bevel=0.02, roughness=0.3))
    d = P.Decal(160, 128)
    d.engrave(P.rect(8, 8, 152, 120), width=4, depth=150)
    d.engrave([P.spiral(40, 40, 18, 3, 1.3), P.spiral(120, 40, 18, 3, 1.3, cw=-1), P.spiral(40, 92, 18, 3, 1.3, cw=-1), P.spiral(120, 92, 18, 3, 1.3)], width=3, depth=160)
    parts.append(box_decal("TPommel", (0.34, 0.32, 0.44), (0, -0.78, 0), GOLD, decal_file("tide_pommel", d), bevel=0.035, roughness=0.3))
    for side in (-1, 1):
        claw = C.box("TClaw%d" % side, (0.2, 0.2, 0.1), (0, -1.0, side * 0.13), gold, bevel=0.02)
        claw.rotation_euler = (side * 0.35, 0, 0)
        C.apply_transforms([claw])
        parts.append(claw)
    glow.append(gem("TGemPommel", 0.2, 0.09, (0, -0.78, 0), 6, gm, dome=0.6))
    tip = Vector((0, 1.08 + 3.8, 0.31 + 0.5))
    INFO["tide_katana"] = (Vector((0, 1.08, 0)), tip)
    return parts, glow, 25


BUILD = {"brown_katana": brown_katana, "jade_katana": jade_katana, "tide_katana": tide_katana}
# every other katana in Katanas.lua (tier swords past blue, shop swords, boss drops)
D.setup(DECALS)
BUILD.update(D.BUILD)
SIZES = {"brown_katana": 512, "jade_katana": 1024, "tide_katana": 1024}
SIZES.update(D.SIZES)


def export(kid, parts, glow, sharp=30):
    name = "HeroKatana_" + kid
    png = os.path.join(TEX, name + ".png")
    size = SIZES.get(kid, 512)
    weights = {p.name: 1.6 for p in parts if "Blade" in p.name}
    if kid in D.BUILD:
        K.fix_uv_aspect(parts)  # keep the blade's atlas island unsquashed (the first three predate this)
    bake.bake_atlas(parts, png, name, size=size, ao=0.4, ao_distance=0.08, ao_samples=256, weights=weights)
    body = C.merge(parts, name)
    if "Decal" in body.data.uv_layers:
        body.data.uv_layers.remove(body.data.uv_layers["Decal"])
    objs = [body]
    if glow:
        objs.append(C.merge(glow, name + "__Glow"))
    for o in objs:
        H.triangulate(o)
        C.shade_auto(o, sharp)
    return objs


def main():
    C.reset_scene()
    shipped = []
    for kid, fn in BUILD.items():
        if ONLY and kid not in ONLY:
            continue
        parts, glow, sharp = fn()
        if kid in K.INFO:
            INFO[kid] = K.INFO[kid]
        objs = export(kid, parts, glow, sharp)
        shipped += objs
        H.studio_render(os.path.join(PREV, kid + ".png"), objs, view=(-1, 0, 0), up=(0, 1, 0), size=(700, 1400))
        H.studio_render(os.path.join(PREV, kid + "_34.png"), objs, view=(-1, -0.5, 0.35), up=(0, 1, 0), size=(700, 1400), ortho=False)
    notes = "hero katanas; blade base/tip per id: " + "; ".join(
        "%s base %s tip %s" % (k, tuple(round(c, 3) for c in C.to_roblox(b)), tuple(round(c, 3) for c in C.to_roblox(tp)))
        for k, (b, tp) in INFO.items())
    man = os.path.join(OUT, "HeroKatanas.lua")
    C.write_manifest(man, "hero_katanas.py", shipped, notes)
    # the game needs each blade's base and tip for the swing trail (KatanaBuilder.finish)
    lines = open(man).read().split("\n")
    for i, line in enumerate(lines):
        for k, (b, tp) in INFO.items():
            if line.startswith('\t["HeroKatana_%s"]' % k):
                extra = ", BladeBase = Vector3.new(%.3f, %.3f, %.3f), BladeTip = Vector3.new(%.3f, %.3f, %.3f)" % (C.to_roblox(b) + C.to_roblox(tp))
                lines[i] = line[:-3] + extra + " },"
    open(man, "w").write("\n".join(lines))
    C.export_fbx(os.path.join(OUT, "NinjaSim_HeroKatanas.fbx"), shipped, embed=True)
    for o in shipped:
        print("MESH", o.name, sum(len(p.vertices) - 2 for p in o.data.polygons), "tris")


main()
