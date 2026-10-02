"""NinjaSim full-body ninja suit (v2). Replaces the blocky avatar with sculpted,
clothed body pieces, one per R15 body part, each centred on that part and facing
Blender +Y (= Roblox -Z). The game hides the avatar's own parts and scales every
piece by (part size / reference size), so the suit also fits R6 and scaled avatars.

  Part (reference size)          pieces
  Head 1.2 cube                  NSuitHood  Cloth Mask Band Plate Eyes
  UpperTorso 2 x 1.6 x 1         NSuitTorso Cloth Lapel Strap Gear Plate Rim
  LowerTorso 2 x 0.4 x 1         NSuitHips  Cloth Belt Gear
  UpperArm 1 x 1.169 x 1         NSuitArm   Cloth Plate Rim      (outer side +X)
  LowerArm 1 x 1.052 x 1         NSuitForearm Cloth Wrap Plate   (outer side +X)
  Hand 1 x 0.3 x 1               NSuitHandR / NSuitHandL  Glove Cuff
  UpperLeg 1 x 1.217 x 1         NSuitThigh Cloth, NSuitHolster Gear (right leg)
  LowerLeg 1 x 1.193 x 1         NSuitShin  Cloth Wrap Plate
  Foot 1 x 0.3 x 1               NSuitFootR / NSuitFootL  Cloth Sole
  extras                         NSuitScarf, NSuitCape Cloth Hem, NSuitHorns, NSuitHalo

Run: python3 tools/blender/ninja.py <out_dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common as C  # noqa: E402
import sculpt as S  # noqa: E402
from common import rgb  # noqa: E402
from shapes import ribbon, shell, swept, tube  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ninja"
os.makedirs(OUT, exist_ok=True)
C.reset_scene()

M = {
    "suit": C.material("Suit", rgb(40, 40, 52), roughness=0.85, roblox="Fabric"),
    "wrap": C.material("Wrap", rgb(70, 66, 80), roughness=0.9, roblox="Fabric"),
    "mask": C.material("MaskCloth", rgb(26, 26, 34), roughness=0.9, roblox="Fabric"),
    "trim": C.material("Trim", rgb(200, 40, 40), roughness=0.8, roblox="Fabric"),
    "leather": C.material("Leather", rgb(80, 52, 36), roughness=0.6, roblox="Leather"),
    "metal": C.material("Metal", rgb(150, 155, 165), metallic=0.75, roughness=0.3, roblox="Metal"),
    "dark": C.material("Sole", rgb(24, 22, 24), roughness=0.8, roblox="SmoothPlastic"),
    "eyes": C.material("Eyes", rgb(255, 255, 255), emission=rgb(255, 255, 255), strength=1.0, roblox="Neon"),
    "horn": C.material("Horn", rgb(235, 225, 205), roughness=0.5, roblox="SmoothPlastic"),
    "glow": C.material("Glow", rgb(255, 220, 120), emission=rgb(255, 220, 120), strength=3.0, roblox="Neon"),
}
objects = []


def group(name, parts, mat, tris=None):
    o = C.merge(parts, name, M[mat]) if len(parts) > 1 else parts[0]
    o.name = name
    o.data.name = name
    o.data.materials.clear()
    o.data.materials.append(M[mat])
    if tris:
        o = S.budget(o, tris)
        o.name = name
        o.data.name = name
    objects.append(o)
    return o


def band_on(name, pts, normals, width, target, mat, thick=0.045, offset=0.012):
    """A strap that hugs `target`: flat strip -> shrinkwrap -> thickness outward."""
    pts = [Vector(p) for p in pts]
    verts, faces = [], []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = Vector(normals[i]).normalized()
        n = (n - t * n.dot(t)).normalized()
        a = n.cross(t).normalized()
        verts += [p - a * width / 2, p + a * width / 2]
    for i in range(len(pts) - 1):
        k = 2 * i
        faces.append((k, k + 2, k + 3, k + 1))
    o = C.mesh_object(name, verts, faces, M[mat])
    sub = o.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    o = S._bake(o, name, M[mat])
    o = S.shrink_onto(o, target, offset)
    s = o.modifiers.new("S", "SOLIDIFY")
    s.thickness = thick
    s.offset = 1.0
    o = S._bake(o, name, M[mat])
    return o


def star(name, r_out, r_in, thick, mat, points=4):
    pts = []
    for k in range(points * 2):
        a = math.pi / 2 + k * math.pi / points
        r = r_out if k % 2 == 0 else r_in
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return C.extrude_outline(name, pts, thick, M[mat], axis="Y", bevel=0.008)


def place(o, loc=(0, 0, 0), rot=(0, 0, 0)):
    o.rotation_euler = rot
    o.location = loc
    C.apply_transforms([o])
    return o


# ================================================================== head: hood + mask
HOOD_C, HOOD_R, HOOD_S, HOOD_P = (0.0, -0.02, 0.05), 0.73, (1.0, 1.04, 1.03), 3.2
COWL = [(-0.42, 0.7, 0.74), (-0.58, 0.64, 0.62), (-0.76, 0.6, 0.44)]  # neck cowl, tucks into the torso


def front_angle(p):
    return math.degrees(math.atan2(p.x, p.y))


def in_slit(p):
    return p.y > 0.2 and -0.12 < p.z < 0.14 and abs(front_angle(p)) < 56


def in_mask(p):
    return p.y > 0.0 and p.z <= -0.12 and abs(front_angle(p)) < 82


def hood():
    cloth = shell("hood", HOOD_R, HOOD_S, HOOD_C, lambda p: p.z > -0.62 and not in_slit(p) and not in_mask(p), M["suit"], power=HOOD_P, segs=56, rings=36)
    # soft wrinkles: the cloth gathers toward the knot at the back
    S.displace(cloth, lambda co, n: 0.012 * math.sin(math.atan2(co.x, -co.y) * 9) * max(0.0, -co.y) * max(0.0, 0.5 - co.z))
    drape = tube("drape", COWL, M["suit"], n=56, power=2.4, thick=0.04, arc=(math.radians(160), math.radians(380)))
    S.displace(drape, S.folds(count=11, depth=0.01, center=(0, 0)))
    group("NSuitHood__Cloth", [cloth, drape], "suit", 5000)
    mask = shell("mask", HOOD_R + 0.012, HOOD_S, HOOD_C, lambda p: p.z > -0.66 and in_mask(p), M["mask"], power=HOOD_P, segs=56, rings=36)
    bib = tube("bib", [(z, hx + 0.014, hy + 0.016) for (z, hx, hy) in COWL], M["mask"], n=40, power=2.4, thick=0.035, arc=(math.radians(16), math.radians(164)))
    S.displace(bib, lambda co, n: 0.012 * math.sin(co.x * 14) * max(0.0, -0.45 - co.z) * 3)
    fold = tube("fold", [(-0.2, 0.752, 0.772), (-0.12, 0.758, 0.778)], M["mask"], n=48, power=HOOD_P, thick=0.035, arc=(math.radians(18), math.radians(162)))
    group("NSuitHood__Mask", [mask, bib, fold], "mask", 3000)
    band = tube("band", [(0.2, 0.748, 0.782), (0.38, 0.738, 0.772)], M["trim"], n=56, power=HOOD_P, thick=0.05)
    knot = S.ellipsoid("knot", (0.14, 0.1, 0.12), (0, -0.82, 0.29), M["trim"])
    tails = []
    for side in (-1, 1):
        pts, normals, widths = [], [], []
        for i in range(12):
            t = i / 11
            pts.append((side * (0.06 + 0.3 * t), -0.84 - 0.95 * t, 0.29 - 0.45 * t + 0.08 * math.sin(t * 8 + side)))
            normals.append((side * 0.8 * math.cos(t * 5), 0.0, 1.0))
            widths.append(0.18 - 0.05 * t)
        tails.append(ribbon("tail", pts, normals, widths, 0.035, M["trim"]))
    group("NSuitHood__Band", [band, knot] + tails, "trim", 2500)
    plate = tube("plate", [(0.212, 0.802, 0.832), (0.368, 0.792, 0.822)], M["metal"], n=12, power=HOOD_P, thick=0.035, arc=(math.radians(64), math.radians(116)))
    emblem = star("emblem", 0.06, 0.022, 0.03, "metal")
    place(emblem, (0, 0.84, 0.29))
    group("NSuitHood__Plate", [plate, emblem], "metal")
    eyes = []
    for side in (-1, 1):
        outline = []
        for k in range(16):
            a = math.tau * k / 16
            u = 0.125 * math.cos(a)
            v = 0.05 * math.sin(a) * (1.0 - 0.45 * max(0.0, math.cos(a) * side))
            outline.append((u, v))
        e = C.extrude_outline("eye", outline, 0.04, M["eyes"], axis="Y")
        place(e, (side * 0.2, 0.62, 0.02), (0, math.radians(side * -14), math.radians(side * -20)))
        eyes.append(e)
    group("NSuitHood__Eyes", eyes, "eyes")


# ================================================================== upper torso
def torso():
    core = S.lofted("core", [(-0.84, 0.68, 0.4), (-0.5, 0.7, 0.41), (-0.1, 0.8, 0.44), (0.3, 0.92, 0.47), (0.58, 0.96, 0.46), (0.74, 0.84, 0.41), (0.84, 0.56, 0.32), (0.9, 0.3, 0.25)], M["suit"], power=2.7)
    delts = [S.ellipsoid("delt", (0.34, 0.38, 0.32), (sx * 0.8, 0.0, 0.5), M["suit"]) for sx in (-1, 1)]
    pecs = [S.ellipsoid("pec", (0.36, 0.17, 0.25), (sx * 0.3, 0.3, 0.32), M["suit"]) for sx in (-1, 1)]
    lats = S.ellipsoid("lats", (0.78, 0.2, 0.42), (0, -0.27, 0.22), M["suit"])
    neck = S.lofted("neck", [(0.72, 0.27, 0.25), (1.0, 0.25, 0.23)], M["suit"])
    body = S.fuse([core, lats, neck] + delts + pecs, "torso", M["suit"], voxel=0.028, smooth=8)
    # cloth pulled in by the belt, and loose folds across the stomach
    S.displace(body, lambda co, n: 0.018 * math.sin(co.x * 10 + co.z * 4) * max(0.0, 1 - abs(co.z + 0.62) / 0.3))
    body = group("NSuitTorso__Cloth", [body], "suit", 5000)
    # crossed gi lapels (left over right) that follow the chest
    lapels = []
    for side, bottom_x, bottom_z, lift in ((-1, 0.36, -0.82, 0.02), (1, -0.1, -0.2, 0.0)):
        pts, normals = [], []
        for i in range(6):  # back of the neck, over the shoulder
            t = i / 5
            pts.append((side * (0.12 + 0.2 * t), -0.3 + 0.55 * t, 0.84 + 0.04 * math.sin(t * math.pi)))
            normals.append((0, -0.6 + 1.2 * t, 1.0))
        for i in range(1, 10):  # down across the chest
            t = i / 9
            pts.append((side * 0.32 + (bottom_x - side * 0.32) * t, 0.3 + 0.2 * t, 0.82 - (0.82 - bottom_z) * t))
            normals.append((0, 1, 0.3 * (1 - t)))
        lapels.append(band_on("lapel", pts, normals, 0.3, body, "trim", thick=0.05, offset=0.012 + lift))
    group("NSuitTorso__Lapel", lapels, "trim", 2500)
    # leather harness: left shoulder to right hip, front and back
    straps = []
    for back in (False, True):
        y = -0.5 if back else 0.5
        pts = [(-0.62 + 1.2 * t, y * (0.9 + 0.1 * math.sin(t * math.pi)), 0.78 - 1.5 * t) for t in [i / 10 for i in range(11)]]
        straps.append(band_on("harness", pts, [(0, 1 if not back else -1, 0.2)] * 11, 0.16, body, "leather", thick=0.04, offset=0.06))
    top = [(-0.62, 0.5, 0.78), (-0.66, 0.2, 0.9), (-0.66, -0.2, 0.9), (-0.62, -0.5, 0.78)]
    straps.append(band_on("harness_top", top, [(0, 0.3, 1), (0, 0.1, 1), (0, -0.1, 1), (0, -0.3, 1)], 0.16, body, "leather", thick=0.04, offset=0.06))
    group("NSuitTorso__Strap", straps, "leather", 1500)
    # shuriken on the chest strap + buckle
    gear = [place(star("shuriken", 0.15, 0.045, 0.03, "metal"), (-0.14, 0.6, 0.3), (0, 0, 0)),
            place(C.box("buckle", (0.2, 0.05, 0.18), (0, 0, 0), M["metal"], bevel=0.02), (0.32, 0.56, -0.35), (0, 0, math.radians(-40)))]
    group("NSuitTorso__Gear", gear, "metal")
    cuirass(body)
    return body


def waist(z):
    """Half width/depth of the torso cloth at height z (matches the core loft)."""
    pts = [(-0.84, 0.68, 0.4), (-0.5, 0.7, 0.41), (-0.1, 0.8, 0.44), (0.3, 0.92, 0.47), (0.58, 0.96, 0.46)]
    for (z0, x0, y0), (z1, x1, y1) in zip(pts, pts[1:]):
        if z <= z1:
            t = max(0.0, (z - z0) / (z1 - z0))
            return x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
    return pts[-1][1], pts[-1][2]


def cuirass(body):
    """Armour tiers: a samurai do. Four laced lames around the belly, front and back
    chest plates, and shoulder straps (watagami) holding them together."""
    plates, laces = [], []
    for i in range(4):
        top = 0.08 - i * 0.17
        hx, hy = waist(top)
        hx, hy = hx + 0.08, hy + 0.08
        plates.append(tube("lame", [(top - 0.2, hx + 0.02, hy + 0.02), (top - 0.1, hx + 0.012, hy + 0.012), (top, hx, hy)], M["metal"], n=56, power=3.0, thick=0.04))
        laces.append(tube("lace", [(top - 0.215, hx + 0.035, hy + 0.035), (top - 0.185, hx + 0.033, hy + 0.033)], M["trim"], n=56, power=3.0, thick=0.025))
        for k in range(10):  # lacing knots along each lame
            a = math.tau * (k + 0.5 * (i % 2)) / 10
            c, s = math.cos(a), math.sin(a)
            x = (hx + 0.03) * math.copysign(abs(c) ** (2 / 3.0), c)
            y = (hy + 0.03) * math.copysign(abs(s) ** (2 / 3.0), s)
            laces.append(S.ellipsoid("knot", (0.03, 0.03, 0.045), (x, y, top - 0.1), M["trim"], segs=10, rings=6))
    hx, hy = waist(0.3)
    for a0, a1 in ((22, 158), (202, 338)):
        arc = (math.radians(a0), math.radians(a1))
        plates.append(tube("mune", [(0.06, hx + 0.02, hy + 0.1), (0.3, hx + 0.08, hy + 0.12), (0.5, hx + 0.02, hy + 0.08)], M["metal"], n=36, power=2.6, thick=0.05, arc=arc))
        laces.append(tube("muneRim", [(0.47, hx + 0.035, hy + 0.1), (0.53, hx + 0.03, hy + 0.09)], M["trim"], n=36, power=2.6, thick=0.035, arc=arc))
    for sx in (-1, 1):
        pts = [(sx * 0.5, 0.56, 0.48), (sx * 0.52, 0.34, 0.76), (sx * 0.52, 0.0, 0.86), (sx * 0.52, -0.34, 0.76), (sx * 0.5, -0.56, 0.48)]
        nrm = [(0, 1, 0.4), (0, 0.6, 1), (0, 0, 1), (0, -0.6, 1), (0, -1, 0.4)]
        laces.append(band_on("watagami", pts, nrm, 0.2, body, "trim", thick=0.045, offset=0.05))
    group("NSuitTorso__Plate", plates, "metal", 4000)
    group("NSuitTorso__Rim", laces, "trim", 3000)


# ================================================================== lower torso: hips + obi
def hips():
    core = S.lofted("hips", [(-0.34, 0.68, 0.42), (-0.12, 0.74, 0.45), (0.12, 0.74, 0.45), (0.3, 0.7, 0.43)], M["suit"], power=2.8)
    seat = [S.ellipsoid("seat", (0.3, 0.22, 0.26), (sx * 0.3, -0.16, -0.12), M["suit"]) for sx in (-1, 1)]
    body = S.fuse([core] + seat, "hips", M["suit"], voxel=0.028, smooth=6)
    group("NSuitHips__Cloth", [body], "suit", 2500)
    obi = tube("obi", [(-0.14, 0.78, 0.5), (0.04, 0.795, 0.51), (0.2, 0.78, 0.5)], M["trim"], n=48, power=3.0, thick=0.06)
    bow = [S.ellipsoid("knot", (0.14, 0.1, 0.13), (0, -0.58, 0.03), M["trim"])]
    for side in (-1, 1):
        bow.append(S.ellipsoid("loop", (0.24, 0.07, 0.13), (side * 0.22, -0.6, 0.06), M["trim"], rot=(0, math.radians(side * 20), 0)))
        pts = [(side * (0.06 + 0.1 * t), -0.62 - 0.08 * t, -0.02 - 0.6 * t) for t in [i / 7 for i in range(8)]]
        bow.append(ribbon("tail", pts, [(0, -1, 0)] * 8, [0.16 + 0.04 * (i / 7) for i in range(8)], 0.035, M["trim"]))
    group("NSuitHips__Belt", [obi] + bow, "trim", 2500)
    pouch = S.ellipsoid("pouch", (0.1, 0.15, 0.16), (-0.8, 0.04, -0.12), M["leather"], power=3.2)
    flap = S.ellipsoid("flap", (0.04, 0.16, 0.09), (-0.9, 0.04, -0.02), M["leather"], power=3.0)
    group("NSuitHips__Gear", [pouch, flap], "leather", 800)


# ================================================================== arms
def arm():
    sleeve = S.lofted("sleeve", [(-0.72, 0.13, 0.13), (-0.66, 0.3, 0.3), (-0.52, 0.35, 0.35), (-0.1, 0.36, 0.36), (0.35, 0.38, 0.38), (0.58, 0.36, 0.36), (0.7, 0.26, 0.26), (0.76, 0.1, 0.1)], M["suit"], power=2.2, n=36)
    S.displace(sleeve, lambda co, n: 0.016 * math.sin(co.z * 26 + math.atan2(co.y, co.x) * 2) * max(0.0, 1 - abs(co.z + 0.35) / 0.3))
    group("NSuitArm__Cloth", [S.subdivide(sleeve, 1)], "suit", 2500)
    plates, rims = [], []
    for i in range(3):
        top = 0.66 - i * 0.24
        r = 0.45 + i * 0.04
        lame = tube("lame", [(top - 0.3, r + 0.07, r), (top, r, r - 0.02)], M["metal"], n=22, power=2.4, thick=0.05, arc=(math.radians(-80), math.radians(80)))
        rim = tube("rim", [(top - 0.33, r + 0.085, r + 0.01), (top - 0.27, r + 0.08, r + 0.005)], M["trim"], n=22, power=2.4, thick=0.035, arc=(math.radians(-82), math.radians(82)))
        for o in (lame, rim):
            place(o, (0, 0, 0), (0, math.radians(-10 - i * 4), 0))
        plates.append(lame)
        rims.append(rim)
    cap = shell("cap", 0.47, (1.0, 1.0, 0.55), (0.02, 0, 0.58), lambda p: p.z > 0.55 and p.x > -0.2, M["metal"], thick=0.05, segs=32, rings=18)
    plates.append(cap)
    group("NSuitArm__Plate", plates, "metal", 2500)
    group("NSuitArm__Rim", rims, "trim", 1500)


def forearm():
    fore = S.lofted("fore", [(-0.6, 0.1, 0.1), (-0.55, 0.24, 0.24), (-0.45, 0.27, 0.27), (0.0, 0.3, 0.3), (0.35, 0.32, 0.32), (0.55, 0.3, 0.3), (0.64, 0.12, 0.12)], M["suit"], power=2.2, n=32)
    group("NSuitForearm__Cloth", [S.subdivide(fore, 1)], "suit", 2000)
    wrap = S.spiral_wrap("wrap", -0.5, 0.22, 0.28, 6.0, 0.13, 0.03, M["wrap"], taper=-0.14, steps=120)
    group("NSuitForearm__Wrap", [wrap], "wrap", 2000)
    base = S.lofted("tmp", [(-0.5, 0.3, 0.3), (0.0, 0.33, 0.33), (0.35, 0.36, 0.36)], M["metal"], power=2.2, n=40, caps=False)
    base = S.subdivide(base, 2)
    tekko = S.extract(base, "tekko", lambda c, n: c.x > 0.15 and -0.44 < c.z < 0.3, M["metal"], offset=0.02, thick=0.045)
    bpy.data.objects.remove(base)
    group("NSuitForearm__Plate", [tekko], "metal", 800)


def hand(side):
    s = 1 if side == "R" else -1
    palm = S.ellipsoid("palm", (0.27, 0.3, 0.24), (0, 0.02, -0.2), M["wrap"], power=3.0)
    knuckles = [S.ellipsoid("knuckle", (0.08, 0.09, 0.08), (x, 0.27, -0.13), M["wrap"]) for x in (-0.17, -0.06, 0.06, 0.17)]
    thumb = S.ellipsoid("thumb", (0.09, 0.16, 0.09), (-0.23, 0.18, -0.16), M["wrap"], rot=(0.3, 0.0, 0.6))
    glove = S.fuse([palm, thumb] + knuckles, "glove", M["wrap"], voxel=0.022, smooth=5)
    cuff = tube("cuff", [(-0.02, 0.29, 0.29), (0.14, 0.31, 0.31)], M["trim"], n=32, power=2.4, thick=0.05)
    if s < 0:
        for o in (glove, cuff):
            o.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
            o.data.flip_normals()
    group("NSuitHand%s__Glove" % side, [glove], "wrap", 1500)
    group("NSuitHand%s__Cuff" % side, [cuff], "trim")


# ================================================================== legs
def thigh():
    pants = S.lofted("pants", [(-0.83, 0.12, 0.12), (-0.78, 0.36, 0.37), (-0.66, 0.43, 0.44), (-0.45, 0.44, 0.45), (-0.1, 0.46, 0.47), (0.3, 0.47, 0.48), (0.58, 0.44, 0.45), (0.7, 0.3, 0.31), (0.74, 0.1, 0.1)], M["suit"], power=2.3, n=40)
    S.displace(pants, lambda co, n: 0.014 * math.sin(math.atan2(co.y, co.x) * 8) * max(0.0, min(1.0, (0.2 - co.z) / 0.6)))
    group("NSuitThigh__Cloth", [S.subdivide(pants, 1)], "suit", 2500)
    ring = tube("ring", [(0.06, 0.49, 0.5), (0.16, 0.495, 0.505)], M["leather"], n=36, power=2.3, thick=0.04)
    holster = S.ellipsoid("holster", (0.07, 0.16, 0.34), (0.53, 0.0, -0.08), M["leather"], power=3.0)
    handle = swept("handle", [(0.55, 0.0, 0.18), (0.55, 0.0, 0.42)], [0.035, 0.03], M["dark"], n=8)
    loop = tube("loop", [(-0.015, 0.07, 0.07), (0.015, 0.07, 0.07)], M["metal"], n=16, power=2.0, thick=0.02)
    place(loop, (0.55, 0.0, 0.5), (math.pi / 2, 0, 0))
    group("NSuitHolster__Gear", [ring, holster, handle, loop], "leather", 1500)


def shin():
    leg = S.lofted("shin", [(-0.67, 0.1, 0.1), (-0.6, 0.27, 0.28), (-0.45, 0.29, 0.3), (-0.2, 0.31, 0.32), (0.2, 0.34, 0.35), (0.5, 0.345, 0.355), (0.66, 0.28, 0.29), (0.72, 0.1, 0.1)], M["suit"], power=2.2, n=36)
    group("NSuitShin__Cloth", [S.subdivide(leg, 1)], "suit", 2000)
    wrap = S.spiral_wrap("wrap", -0.56, 0.3, 0.3, 6.5, 0.14, 0.03, M["wrap"], taper=-0.17, steps=130)
    group("NSuitShin__Wrap", [wrap], "wrap", 2200)
    base = S.lofted("tmp", [(-0.5, 0.33, 0.34), (0.0, 0.37, 0.38), (0.4, 0.4, 0.41)], M["metal"], power=2.2, n=40, caps=False)
    base = S.subdivide(base, 2)
    plate = S.extract(base, "suneate", lambda c, n: c.y > 0.14 and -0.46 < c.z < 0.36, M["metal"], offset=0.02, thick=0.045)
    bpy.data.objects.remove(base)
    knee = S.ellipsoid("knee", (0.2, 0.09, 0.18), (0, 0.45, 0.5), M["metal"])
    group("NSuitShin__Plate", [plate, knee], "metal", 1200)


def foot(side):
    s = 1 if side == "R" else -1
    ankle = S.lofted("ankle", [(-0.08, 0.28, 0.28), (0.25, 0.3, 0.31), (0.42, 0.26, 0.26)], M["wrap"], power=2.2)
    body = S.ellipsoid("foot", (0.3, 0.48, 0.17), (0, 0.16, -0.03), M["wrap"], power=2.6)
    big = S.ellipsoid("bigtoe", (0.1, 0.14, 0.11), (-0.15, 0.58, -0.07), M["wrap"])
    toes = S.ellipsoid("toes", (0.17, 0.14, 0.1), (0.1, 0.56, -0.08), M["wrap"])
    tabi = S.fuse([ankle, body, big, toes], "tabi", M["wrap"], voxel=0.02, smooth=3)
    sole = S.extract(tabi, "sole", lambda c, n: n.z < -0.55, M["dark"], offset=-0.01, thick=0.05)
    if s < 0:
        for o in (tabi, sole):
            o.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
            o.data.flip_normals()
    group("NSuitFoot%s__Cloth" % side, [tabi], "wrap", 1800)
    group("NSuitFoot%s__Sole" % side, [sole], "dark", 800)


# ================================================================== tier extras
def scarf():
    ring = tube("ring", [(0.66, 0.66, 0.58), (0.78, 0.8, 0.74), (0.92, 0.8, 0.78), (1.04, 0.7, 0.72)], M["trim"], n=48, power=2.4, thick=0.09)
    S.displace(ring, S.folds(count=11, depth=0.025, seed=3))
    tails = []
    for side, length, lift in ((1, 2.4, 0.0), (-1, 1.7, 0.15)):
        pts, normals, widths = [], [], []
        for i in range(16):
            t = i / 15
            pts.append((side * (0.14 + 0.45 * t), -0.58 - length * t, 0.88 - 1.0 * t * t + lift * t + 0.12 * math.sin(t * 9 + side)))
            normals.append((side * 0.5 * math.sin(t * 6), 0.2, 1))
            widths.append(0.42 - 0.12 * t)
        tails.append(ribbon("tail", pts, normals, widths, 0.045, M["trim"]))
    group("NSuitScarf__Cloth", [ring] + tails, "trim", 3500)


def cape():
    nu, nv = 28, 24
    verts, faces = [], []
    for j in range(nv + 1):
        v = j / nv
        z = 0.86 - 3.5 * v
        half = 1.05 + 0.45 * v
        for i in range(nu + 1):
            u = -1 + 2 * i / nu
            fold = 0.09 * math.sin(u * math.pi * 4.5) * v ** 0.7
            wrap = 0.3 * (1 - v) ** 3 * u * u
            y = -0.6 - 0.25 * v - 0.4 * v * v - fold + wrap
            # tattered hem: some columns hang lower than others
            drop = 0.18 * max(0.0, math.sin(u * 17.0) * math.sin(u * 5.3)) * v ** 8
            verts.append((u * half, y, z - drop))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i
            faces.append((a, a + 1, a + nu + 2, a + nu + 1))
    o = C.mesh_object("cape", verts, faces, M["suit"])
    sol = o.modifiers.new("S", "SOLIDIFY")
    sol.thickness = 0.05
    sol.offset = 1.0
    o = S._bake(o, "cape", M["suit"])
    group("NSuitCape__Cloth", [o], "suit", 3000)
    collar = tube("collar", [(0.78, 1.0, 0.5), (0.9, 0.98, 0.5)], M["glow"], n=40, power=2.6, thick=0.05, arc=(math.radians(190), math.radians(350)))
    clasps = [S.ellipsoid("clasp", (0.12, 0.06, 0.12), (side * 0.86, -0.26, 0.84), M["glow"]) for side in (-1, 1)]
    group("NSuitCape__Hem", [collar] + clasps, "glow")


def horns():
    parts = []
    for side in (-1, 1):
        verts = [(side * (0.33 + 0.24 * t + 0.14 * t * t), 0.18 - 0.38 * t * t, 0.5 + 0.66 * t - 0.13 * t * t) for t in [i / 6 for i in range(7)]]
        radii = [0.13 * (1 - i / 6) ** 0.8 + 0.012 for i in range(7)]
        h = S.skin("horn", verts, [(i, i + 1) for i in range(6)], radii, M["horn"], subdiv=2)
        S.displace(h, lambda co, n: 0.012 * math.sin(co.z * 40))
        parts.append(h)
    group("NSuitHorns__Horn", parts, "horn", 2500)


def halo():
    ring = tube("ring", [(1.02, 0.5, 0.5), (1.08, 0.5, 0.5)], M["glow"], n=64, power=2.0, thick=0.06)
    spikes = []
    for k in range(12):
        a = math.tau * k / 12
        sp = C.cylinder("spike", 0.045, 0.26 if k % 2 == 0 else 0.16, (0, 0, 0), M["glow"], 6, radius_top=0.004)
        spikes.append(place(sp, (math.cos(a) * 0.53, math.sin(a) * 0.53, 1.05), (0, math.pi / 2, a)))
    group("NSuitHalo__Ring", [ring] + spikes, "glow")


hood()
torso()
hips()
arm()
forearm()
hand("R")
hand("L")
thigh()
shin()
foot("R")
foot("L")
scarf()
cape()
horns()
halo()

C.write_manifest(os.path.join(OUT, "NinjaManifest.lua"), "ninja.py", objects, "each piece is centred on its R15 body part (see ninja.py), character facing -Z")
C.export_fbx(os.path.join(OUT, "NinjaSim_Ninja.fbx"), objects)
print("TRIS", {o.name: S.tris(o) for o in objects})

# ================================================================== preview
# R15 part centres (Blender coords) for a standing figure; arms slightly out.
LAYOUT = {
    "Head": (0, 0, 5.32), "UpperTorso": (0, 0, 3.92), "LowerTorso": (0, 0, 2.93),
    "RightUpperArm": (1.52, 0, 4.12), "LeftUpperArm": (-1.52, 0, 4.12),
    "RightLowerArm": (1.6, 0.02, 3.1), "LeftLowerArm": (-1.6, 0.02, 3.1),
    "RightHand": (1.64, 0.04, 2.5), "LeftHand": (-1.64, 0.04, 2.5),
    "RightUpperLeg": (0.5, 0, 2.14), "LeftUpperLeg": (-0.5, 0, 2.14),
    "RightLowerLeg": (0.5, 0, 1.03), "LeftLowerLeg": (-0.5, 0, 1.03),
    "RightFoot": (0.5, 0, 0.3), "LeftFoot": (-0.5, 0, 0.3),
}
TILT = {"RightUpperArm": -0.12, "RightLowerArm": -0.08, "RightHand": -0.08, "LeftUpperArm": 0.12, "LeftLowerArm": 0.08, "LeftHand": 0.08}
WEAR = [  # (piece prefix, parts, feature)
    ("NSuitHood", ["Head"], None), ("NSuitTorso", ["UpperTorso"], None), ("NSuitHips", ["LowerTorso"], None),
    ("NSuitArm", ["RightUpperArm", "LeftUpperArm"], None), ("NSuitForearm", ["RightLowerArm", "LeftLowerArm"], None),
    ("NSuitHandR", ["RightHand"], None), ("NSuitHandL", ["LeftHand"], None),
    ("NSuitThigh", ["RightUpperLeg", "LeftUpperLeg"], None), ("NSuitHolster", ["RightUpperLeg"], None),
    ("NSuitShin", ["RightLowerLeg", "LeftLowerLeg"], None),
    ("NSuitFootR", ["RightFoot"], None), ("NSuitFootL", ["LeftFoot"], None),
    ("NSuitScarf", ["UpperTorso"], "Scarf"), ("NSuitCape", ["UpperTorso"], "Cape"),
    ("NSuitHorns", ["Head"], "Horns"), ("NSuitHalo", ["Head"], "Halo"),
]
TIERS = [
    # x, primary, secondary, trim, eyes, features
    (-4.2, rgb(112, 74, 46), rgb(74, 48, 30), rgb(196, 150, 96), rgb(30, 20, 15), set()),
    (0.0, rgb(34, 78, 170), rgb(18, 38, 92), rgb(110, 220, 255), rgb(120, 220, 255), {"Scarf"}),
    (4.2, rgb(22, 22, 26), rgb(40, 38, 44), rgb(200, 40, 50), rgb(255, 40, 40), {"Scarf", "Armor", "Cape", "Horns"}),
]
shown = []
for (ox, primary, secondary, trim, eyes, feats) in TIERS:
    mats = {
        "Cloth": C.material("c%s" % ox, primary, roughness=0.85), "Mask": C.material("k%s" % ox, [c * 0.45 for c in primary], roughness=0.9),
        "Wrap": C.material("w%s" % ox, secondary, roughness=0.9), "Glove": C.material("g%s" % ox, secondary, roughness=0.8),
        "Band": C.material("b%s" % ox, trim, roughness=0.8), "Lapel": C.material("l%s" % ox, trim, roughness=0.8),
        "Belt": C.material("t%s" % ox, trim, roughness=0.8), "Cuff": C.material("u%s" % ox, trim, roughness=0.8),
        "Rim": C.material("r%s" % ox, trim, roughness=0.7), "Eyes": C.material("e%s" % ox, eyes, emission=eyes, strength=5.0),
        "Hem": C.material("h%s" % ox, trim, emission=trim, strength=2.0), "Ring": C.material("h2%s" % ox, trim, emission=trim, strength=3.0),
    }
    skin = C.material("skin%s" % ox, rgb(234, 190, 150), roughness=0.6)
    face = S.ellipsoid("face", (0.58, 0.58, 0.6), (ox, 0, LAYOUT["Head"][2]), skin)
    shown.append(face)
    for prefix, parts, feat in WEAR:
        if feat and feat not in feats:
            continue
        for o in [o for o in objects if o.name.startswith(prefix + "__")]:
            grp = o.name.split("__")[1]
            if grp == "Plate" and "Armor" not in feats and prefix != "NSuitHood":
                continue
            if grp == "Rim" and "Armor" not in feats:
                continue
            if prefix == "NSuitTorso" and grp in ("Strap", "Gear") and "Armor" in feats:
                continue
            for part in parts:
                d = o.copy()
                d.data = o.data.copy()
                bpy.context.scene.collection.objects.link(d)
                if grp in mats and prefix not in ("NSuitHolster",) and not (prefix == "NSuitCape" and grp == "Hem"):
                    d.data.materials.clear()
                    d.data.materials.append(mats[grp])
                flip = part.startswith("Left") and prefix in ("NSuitArm", "NSuitForearm")
                if flip:
                    d.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
                if part in TILT:
                    d.data.transform(Matrix.Rotation(TILT[part], 4, "Y"))
                x, y, z = LAYOUT[part]
                d.location = (x + ox, y, z)
                shown.append(d)
C.apply_transforms(shown)
ground = C.box("ground", (20, 12, 0.2), (0, 0, 0.02), C.material("Floor", rgb(64, 70, 66), roughness=1))
shown.append(ground)
for o in bpy.data.objects:
    if o.type == "MESH":
        o.hide_render = o not in shown
C.render_preview(os.path.join(OUT, "preview_ninja.png"), shown, size=(1600, 1000), camera_dir=(0.3, 1.0, 0.28), margin=0.6, samples=48, background=(0.42, 0.46, 0.55))
C.render_preview(os.path.join(OUT, "preview_ninja_back.png"), shown, size=(1600, 1000), camera_dir=(-0.45, -1.0, 0.35), margin=0.6, samples=32, background=(0.42, 0.46, 0.55))
print("OK", len(objects), "objects")
