"""NinjaSim ninja outfit: hood + mask, headband, gi lapels, obi belt, bracers, shin
guards, layered shoulder armour, scarf, cape, oni horns and halo.

Every piece is modelled around a *reference body part* of the default R15 blocky
rig, centred on that part (the part's centre is the origin), character facing
Blender +Y (= Roblox -Z). The game scales each piece by (actual part size /
reference size) and welds it on, so it fits R15, R6 and scaled avatars.

  Head        1.2 x 1.2 x 1.2      NinjaHood, NinjaHorns, NinjaHalo
  UpperTorso  2 x 1.6 x 1          NinjaGi__Lapel, NinjaScarf, NinjaCape
  LowerTorso  2 x 0.4 x 1          NinjaBelt
  UpperArm    1 x 1.169 x 1        NinjaShoulder (outer side +X = right arm)
  LowerArm    1 x 1.052 x 1        NinjaBracer (outer side +X = right arm)
  LowerLeg    1 x 1.193 x 1        NinjaShin (front +Y)

Run: python3 tools/blender/outfit.py <out_dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common as C  # noqa: E402
from common import rgb  # noqa: E402
from shapes import ribbon, shell, smooth, solidify, swept, tube  # noqa: E402,F401

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/outfit"
os.makedirs(OUT, exist_ok=True)
C.reset_scene()

M = {
    "cloth": C.material("Cloth", rgb(40, 40, 52), roughness=0.9, roblox="Fabric"),
    "mask": C.material("MaskCloth", rgb(26, 26, 34), roughness=0.9, roblox="Fabric"),
    "trim": C.material("Trim", rgb(200, 40, 40), roughness=0.8, roblox="Fabric"),
    "metal": C.material("Metal", rgb(150, 155, 165), metallic=0.7, roughness=0.35, roblox="Metal"),
    "eyes": C.material("Eyes", rgb(255, 255, 255), emission=rgb(255, 255, 255), strength=1.0, roblox="Neon"),
    "horn": C.material("Horn", rgb(235, 225, 205), roughness=0.5, roblox="SmoothPlastic"),
    "glow": C.material("Glow", rgb(255, 220, 120), emission=rgb(255, 220, 120), strength=3.0, roblox="Neon"),
}
objects = []


def keep(o, name):
    o.name = name
    o.data.name = name
    objects.append(o)
    return o


def group(name, parts, mat):
    return keep(C.merge(parts, name, M[mat]), name)


# ------------------------------------------------------------------ hood (Head 1.2 cube)
HOOD_C = (0.0, -0.02, 0.05)
HOOD_R = 0.73
HOOD_S = (1.0, 1.04, 1.03)
HOOD_P = 3.2  # boxy enough to cover a Roblox head's rounded corners


def front_angle(p):
    return math.degrees(math.atan2(p.x, p.y))  # 0 = straight ahead (+Y)


def in_slit(p):
    return p.y > 0.2 and -0.13 < p.z < 0.15 and abs(front_angle(p)) < 58


def in_mask(p):
    return p.y > 0.0 and p.z <= -0.13 and abs(front_angle(p)) < 80


def hood():
    cloth = shell("hood", HOOD_R, HOOD_S, HOOD_C, lambda p: p.z > -0.62 and not in_slit(p) and not in_mask(p), M["cloth"], power=HOOD_P)
    # the cowl drapes onto the shoulders at the back and sides
    drape = tube("drape", [(-0.42, 0.66, 0.7), (-0.62, 0.74, 0.76), (-0.8, 0.86, 0.8)], M["cloth"], n=40, power=2.2, thick=0.04, arc=(math.radians(200), math.radians(340)))
    mask = shell("mask", HOOD_R + 0.012, HOOD_S, HOOD_C, lambda p: p.z > -0.66 and in_mask(p), M["mask"], power=HOOD_P)
    # a soft fold where the mask wraps under the eyes
    fold = tube("fold", [(-0.2, 0.75, 0.77), (-0.13, 0.755, 0.775)], M["mask"], n=40, power=HOOD_P, thick=0.03, arc=(math.radians(20), math.radians(160)))
    group("NinjaHood__Cloth", [cloth, drape], "cloth")
    group("NinjaHood__Mask", [mask, fold], "mask")
    # headband ring + knot + two tails flowing back
    band = tube("band", [(0.2, 0.745, 0.78), (0.38, 0.735, 0.77)], M["trim"], n=44, power=HOOD_P, thick=0.05)
    knot = C.blob("knot", 0.13, (0, -0.8, 0.29), M["trim"], subdiv=2, noise=0.08, seed=3, squash=0.75)
    tails = []
    for side in (-1, 1):
        pts, normals, widths = [], [], []
        for i in range(9):
            t = i / 8
            pts.append((side * (0.05 + 0.22 * t), -0.8 - 0.75 * t, 0.29 - 0.38 * t + 0.06 * math.sin(t * 7 + side)))
            normals.append((side * 0.9, 0.0, 1.0))
            widths.append(0.17 - 0.04 * t)
        tails.append(ribbon("tail", pts, normals, widths, 0.035, M["trim"]))
    group("NinjaHood__Band", [band, knot] + tails, "trim")
    # forehead plate: slightly curved, bevelled, with a raised rim
    plate = tube("plate", [(0.215, 0.8, 0.83), (0.365, 0.79, 0.82)], M["metal"], n=10, power=HOOD_P, thick=0.035, arc=(math.radians(66), math.radians(114)))
    group("NinjaHood__Plate", [plate], "metal")
    # eyes: angled almonds sitting on the head surface inside the slit
    eyes = []
    for side in (-1, 1):
        outline = []
        for k in range(14):
            a = 2 * math.pi * k / 14
            u = 0.12 * math.cos(a)
            v = 0.052 * math.sin(a) * (1.0 - 0.35 * max(0.0, math.cos(a) * side))
            outline.append((u, v))
        e = C.extrude_outline("eye", outline, 0.04, M["eyes"], axis="Y")
        e.rotation_euler = (0, math.radians(side * -14), math.radians(side * -18))
        e.location = (side * 0.2, 0.61, 0.03)
        C.apply_transforms([e])
        eyes.append(e)
    group("NinjaHood__Eyes", eyes, "eyes")


# ------------------------------------------------------------------ horns + halo (Head)
def horns():
    parts = []
    for side in (-1, 1):
        pts, radii = [], []
        for i in range(14):
            t = i / 13
            pts.append((side * (0.33 + 0.22 * t + 0.12 * t * t), 0.18 - 0.35 * t * t, 0.5 + 0.62 * t - 0.12 * t * t))
            radii.append(0.12 * (1 - t) ** 0.8 + 0.008)
        parts.append(swept("horn", pts, radii, M["horn"], n=14))
        parts.append(tube("hornring", [(0.0, 0.135, 0.135), (0.05, 0.14, 0.14)], M["horn"], n=16, power=2.0, thick=0.03, center=(side * 0.35, 0.16, 0.55)))
    group("NinjaHorns__Horn", parts, "horn")


def halo():
    ring = tube("ring", [(1.02, 0.5, 0.5), (1.08, 0.5, 0.5)], M["glow"], n=48, power=2.0, thick=0.06)
    spikes = []
    for k in range(10):
        a = 2 * math.pi * k / 10
        s = C.cylinder("spike", 0.045, 0.24, (0, 0, 0), M["glow"], 6, radius_top=0.004)
        s.rotation_euler = (0, math.pi / 2, a)
        s.location = (math.cos(a) * 0.53, math.sin(a) * 0.53, 1.05)
        C.apply_transforms([s])
        spikes.append(s)
    group("NinjaHalo__Ring", [ring] + spikes, "glow")


# ------------------------------------------------------------------ gi lapels (UpperTorso 2 x 1.6 x 1)
def lapels():
    parts = []
    for side, depth in ((1, 0.535), (-1, 0.52)):
        # front: from the shoulder down across the chest (right panel under, left over)
        pts, normals = [], []
        x0 = side * 0.36
        x1 = -side * 0.34 if side > 0 else -side * 0.02
        z1 = -0.8 if side > 0 else -0.12
        for i in range(8):
            t = i / 7
            pts.append((x0 + (x1 - x0) * t, depth, 0.8 - (0.8 - z1) * t))
            normals.append((0, 1, 0))
        # over the shoulder to the back of the neck
        back = [(x0, 0.4, 0.84), (x0 * 0.9, 0.0, 0.86), (x0 * 0.8, -0.4, 0.84), (x0 * 0.7, -0.53, 0.7), (x0 * 0.6, -0.53, 0.45)]
        pts = list(reversed(back)) + pts
        normals = [(0, -1, 0), (0, -1, 0.6), (0, 0, 1), (0, 0.3, 1), (0, 1, 0.6)] + normals
        parts.append(ribbon("lapel", pts, normals, 0.3, 0.06, M["trim"]))
    group("NinjaGi__Lapel", parts, "trim")


# ------------------------------------------------------------------ obi belt (LowerTorso 2 x 0.4 x 1)
def belt():
    obi = tube("obi", [(-0.2, 1.04, 0.54), (0.0, 1.05, 0.55), (0.2, 1.04, 0.54)], M["trim"], n=36, power=6.0, thick=0.06)
    knot = C.blob("knot", 0.2, (0.42, 0.62, 0.0), M["trim"], subdiv=2, noise=0.1, seed=7, squash=0.8)
    loops = []
    for side in (-1, 1):
        lp = C.blob("loop", 0.16, (0.42 + side * 0.24, 0.6, 0.04), M["trim"], subdiv=2, noise=0.06, seed=9 + side, squash=0.55)
        loops.append(lp)
    hangs = []
    for k, (dx, length) in enumerate(((-0.08, 1.0), (0.1, 0.8))):
        pts, normals, widths = [], [], []
        for i in range(8):
            t = i / 7
            pts.append((0.42 + dx + 0.06 * t * (1 if k else -1), 0.64 + 0.08 * t, -0.08 - length * t))
            normals.append((0, 1, 0))
            widths.append(0.2 + 0.05 * t)
        hangs.append(ribbon("hang", pts, normals, widths, 0.04, M["trim"]))
    group("NinjaBelt__Obi", [obi, knot] + loops + hangs, "trim")


# ------------------------------------------------------------------ bracers (LowerArm 1 x 1.052 x 1)
def bracers():
    wrap = tube("wrap", [(-0.5, 0.54, 0.54), (-0.1, 0.55, 0.55), (0.32, 0.575, 0.575)], M["cloth"], n=32, power=4.0, thick=0.05)
    straps = [tube("strap", [(z, 0.6, 0.6), (z + 0.08, 0.6, 0.6)], M["trim"], n=32, power=4.0, thick=0.03) for z in (-0.42, -0.14, 0.14)]
    plate = tube("plate", [(-0.38, 0.6, 0.6), (0.0, 0.615, 0.615), (0.26, 0.63, 0.63)], M["metal"], n=12, power=3.0, thick=0.04, arc=(math.radians(-42), math.radians(42)))
    group("NinjaBracer__Wrap", [wrap], "cloth")
    group("NinjaBracer__Strap", straps, "trim")
    group("NinjaBracer__Plate", [plate], "metal")


# ------------------------------------------------------------------ shin guards (LowerLeg 1 x 1.193 x 1)
def shins():
    wrap = tube("wrap", [(-0.56, 0.54, 0.54), (-0.1, 0.555, 0.555), (0.45, 0.575, 0.575)], M["cloth"], n=32, power=4.0, thick=0.05)
    straps = [tube("strap", [(z, 0.6, 0.6), (z + 0.08, 0.6, 0.6)], M["trim"], n=32, power=4.0, thick=0.03) for z in (-0.46, 0.0, 0.36)]
    plate = tube("plate", [(-0.36, 0.6, 0.62), (0.05, 0.61, 0.635), (0.4, 0.6, 0.625)], M["metal"], n=12, power=3.0, thick=0.04, arc=(math.radians(58), math.radians(122)))
    knee = C.blob("knee", 0.2, (0, 0.6, 0.5), M["metal"], subdiv=2, noise=0.0, squash=0.8)
    knee.scale = (1.0, 0.55, 1.0)
    C.apply_transforms([knee])
    group("NinjaShin__Wrap", [wrap], "cloth")
    group("NinjaShin__Strap", straps, "trim")
    group("NinjaShin__Plate", [plate, knee], "metal")


# ------------------------------------------------------------------ shoulder armour (UpperArm 1 x 1.169 x 1)
def shoulders():
    plates, rims = [], []
    for i in range(3):
        top = 0.62 - i * 0.24
        r = 0.6 + i * 0.045
        lame = tube("lame", [(top - 0.3, r + 0.06, r), (top, r, r - 0.02)], M["metal"], n=18, power=2.4, thick=0.05, arc=(math.radians(-80), math.radians(80)))
        rim = tube("rim", [(top - 0.33, r + 0.075, r + 0.01), (top - 0.27, r + 0.07, r + 0.005)], M["trim"], n=18, power=2.4, thick=0.035, arc=(math.radians(-82), math.radians(82)))
        for o in (lame, rim):
            o.rotation_euler = (0, math.radians(-10 - i * 4), 0)
            C.apply_transforms([o])
        plates.append(lame)
        rims.append(rim)
    cap = shell("cap", 0.62, (1.0, 1.0, 0.55), (0.02, 0, 0.5), lambda p: p.z > 0.5 and p.x > -0.25, M["metal"], thick=0.05, segs=28, rings=16)
    plates.append(cap)
    group("NinjaShoulder__Plate", plates, "metal")
    group("NinjaShoulder__Rim", rims, "trim")


# ------------------------------------------------------------------ scarf (UpperTorso)
def scarf():
    ring = tube("ring", [(0.74, 0.5, 0.42), (0.86, 0.6, 0.5), (0.98, 0.56, 0.47), (1.08, 0.47, 0.4)], M["trim"], n=36, power=2.4, thick=0.08)
    tails = []
    for side, length, lift in ((1, 2.3, 0.0), (-1, 1.6, 0.15)):
        pts, normals, widths = [], [], []
        for i in range(12):
            t = i / 11
            pts.append((side * (0.12 + 0.4 * t), -0.55 - length * t, 0.86 - 0.95 * t * t + lift * t + 0.1 * math.sin(t * 9 + side)))
            normals.append((side * 0.35 * math.sin(t * 6), 0.2, 1))
            widths.append(0.4 - 0.12 * t)
        tails.append(ribbon("tail", pts, normals, widths, 0.045, M["trim"]))
    group("NinjaScarf__Cloth", [ring] + tails, "trim")


# ------------------------------------------------------------------ cape (UpperTorso)
def cape():
    nu, nv = 16, 14
    verts, faces = [], []
    for j in range(nv + 1):
        v = j / nv  # 0 at the shoulders, 1 at the hem
        z = 0.84 - 3.5 * v
        half = 1.08 + 0.4 * v
        for i in range(nu + 1):
            u = -1 + 2 * i / nu
            fold = 0.07 * math.sin(u * math.pi * 3.5) * v ** 0.8
            wrap = 0.28 * (1 - v) ** 3 * u * u  # hugs the shoulders at the top
            y = -0.56 - 0.35 * v * v - fold + wrap
            verts.append((u * half, y, z))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i
            faces.append((a, a + 1, a + nu + 2, a + nu + 1))
    o = C.mesh_object("cape", verts, faces, M["cloth"])
    smooth(o)
    solidify(o, 0.05, 1.0)
    group("NinjaCape__Cloth", [o], "cloth")
    pts, normals = [], []
    for i in range(nu + 1):
        u = -1 + 2 * i / nu
        v = 1.0
        half = 1.08 + 0.4
        fold = 0.07 * math.sin(u * math.pi * 3.5)
        pts.append((u * half, -0.56 - 0.35 - fold - 0.02, 0.84 - 3.5 + 0.06))
        normals.append((0, -1, 0))
    hem = ribbon("hem", pts, normals, 0.14, 0.07, M["glow"])
    clasp = []
    for side in (-1, 1):
        clasp.append(C.blob("clasp", 0.12, (side * 0.8, -0.32, 0.84), M["glow"], subdiv=2, noise=0.0))
    group("NinjaCape__Hem", [hem] + clasp, "glow")


hood()
horns()
halo()
lapels()
belt()
bracers()
shins()
shoulders()
scarf()
cape()

C.write_manifest(os.path.join(OUT, "OutfitManifest.lua"), "outfit.py", objects, "each piece is centred on its reference body part (see outfit.py), character facing -Z")
C.export_fbx(os.path.join(OUT, "NinjaSim_Outfit.fbx"), objects)

# ------------------------------------------------------------------ preview on R15 mannequins
REF = {
    "Head": ((1.2, 1.2, 1.2), (0, 0, 5.3)),
    "UpperTorso": ((2, 1, 1.6), (0, 0, 3.9)),
    "LowerTorso": ((2, 1, 0.4), (0, 0, 2.9)),
    "RightUpperArm": ((1, 1, 1.169), (1.5, 0, 4.115)), "LeftUpperArm": ((1, 1, 1.169), (-1.5, 0, 4.115)),
    "RightLowerArm": ((1, 1, 1.052), (1.5, 0, 3.0)), "LeftLowerArm": ((1, 1, 1.052), (-1.5, 0, 3.0)),
    "RightHand": ((1, 1, 0.3), (1.5, 0, 2.33)), "LeftHand": ((1, 1, 0.3), (-1.5, 0, 2.33)),
    "RightUpperLeg": ((1, 1, 1.217), (0.5, 0, 2.1)), "LeftUpperLeg": ((1, 1, 1.217), (-0.5, 0, 2.1)),
    "RightLowerLeg": ((1, 1, 1.193), (0.5, 0, 0.9)), "LeftLowerLeg": ((1, 1, 1.193), (-0.5, 0, 0.9)),
    "RightFoot": ((1, 1, 0.3), (0.5, 0.1, 0.15)), "LeftFoot": ((1, 1, 0.3), (-0.5, 0.1, 0.15)),
}
PIECES = {  # piece prefix -> (body part, mirrored copy for the left side)
    "NinjaHood": ["Head"], "NinjaHorns": ["Head"], "NinjaHalo": ["Head"],
    "NinjaGi": ["UpperTorso"], "NinjaScarf": ["UpperTorso"], "NinjaCape": ["UpperTorso"],
    "NinjaBelt": ["LowerTorso"],
    "NinjaShoulder": ["RightUpperArm", "LeftUpperArm"], "NinjaBracer": ["RightLowerArm", "LeftLowerArm"],
    "NinjaShin": ["RightLowerLeg", "LeftLowerLeg"],
}
TIERS = [
    # (x offset, body, primary, mask, trim, metal, eyes, pieces)
    (-5.0, rgb(45, 45, 58), rgb(70, 70, 86), rgb(28, 28, 36), rgb(200, 45, 45), rgb(150, 150, 160), rgb(255, 255, 255),
     {"NinjaHood", "NinjaGi", "NinjaBelt", "NinjaBracer", "NinjaShin"}),
    (0.0, rgb(28, 40, 70), rgb(40, 58, 100), rgb(18, 24, 40), rgb(90, 200, 255), rgb(170, 190, 210), rgb(120, 230, 255),
     {"NinjaHood", "NinjaGi", "NinjaBelt", "NinjaBracer", "NinjaShin", "NinjaScarf", "NinjaShoulder"}),
    (5.0, rgb(30, 18, 34), rgb(52, 26, 60), rgb(16, 10, 20), rgb(255, 190, 60), rgb(60, 40, 70), rgb(255, 120, 60),
     {"NinjaHood", "NinjaGi", "NinjaBelt", "NinjaBracer", "NinjaShin", "NinjaScarf", "NinjaShoulder", "NinjaCape", "NinjaHorns", "NinjaHalo"}),
]
shown = []
for (ox, skin, primary, mask, trim, metal, eyes, pieces) in TIERS:
    mats = {
        "Cloth": C.material("pc%d" % ox, primary, roughness=0.9), "Wrap": C.material("pw%d" % ox, primary, roughness=0.9),
        "Mask": C.material("pm%d" % ox, mask, roughness=0.9), "Band": C.material("pt%d" % ox, trim, roughness=0.8),
        "Lapel": C.material("pl%d" % ox, trim, roughness=0.8), "Obi": C.material("po%d" % ox, trim, roughness=0.8),
        "Strap": C.material("ps%d" % ox, trim, roughness=0.8), "Rim": C.material("pr%d" % ox, trim, metallic=0.5, roughness=0.4),
        "Plate": C.material("pp%d" % ox, metal, metallic=0.75, roughness=0.3),
        "Eyes": C.material("pe%d" % ox, eyes, emission=eyes, strength=4.0),
        "Horn": C.material("ph%d" % ox, rgb(240, 230, 210), roughness=0.4),
        "Ring": C.material("pg%d" % ox, trim, emission=trim, strength=3.0), "Hem": C.material("pn%d" % ox, trim, emission=trim, strength=2.0),
    }
    body = C.material("pb%d" % ox, primary, roughness=0.9)
    head_mat = C.material("pk%d" % ox, rgb(234, 190, 150), roughness=0.7)
    for name, (size, pos) in REF.items():
        if name == "Head":  # Roblox's classic head: a rounded cylinder
            prof = [(0, 0), (0.4, 0), (0.52, 0.03), (0.585, 0.12), (0.6, 0.3), (0.6, 0.9), (0.585, 1.08), (0.52, 1.17), (0.4, 1.2), (0, 1.2)]
            b = C.lathe("body_head", prof, 32, head_mat, axis="Z")
            b.location = (pos[0] + ox, pos[1], pos[2] - 0.6)
        else:
            b = C.box("body_" + name, size, (pos[0] + ox, pos[1], pos[2]), body, bevel=0.08)
        shown.append(b)
    for o in list(objects):
        prefix, grp = o.name.split("__")
        if prefix not in pieces:
            continue
        for k, part in enumerate(PIECES[prefix]):
            d = o.copy()
            d.data = o.data.copy()
            bpy.context.scene.collection.objects.link(d)
            d.data.materials.clear()
            d.data.materials.append(mats.get(grp, body))
            if part.startswith("Left") and prefix in ("NinjaShoulder", "NinjaBracer"):
                d.data.transform(Matrix.Rotation(math.pi, 4, "Z"))  # outer side faces -X on the left arm
            pos = REF[part][1]
            d.location = (pos[0] + ox, pos[1], pos[2])
            shown.append(d)
C.apply_transforms(shown)
ground = C.box("ground", (22, 12, 0.2), (0, 0, -0.1), C.material("Floor", rgb(70, 80, 70), roughness=1))
shown.append(ground)
for o in bpy.data.objects:
    if o.type == "MESH":
        o.hide_render = o not in shown
C.render_preview(os.path.join(OUT, "preview_outfits.png"), shown, size=(1500, 900), camera_dir=(0.35, 1.0, 0.25), margin=0.62, samples=40, background=(0.5, 0.55, 0.65))
C.render_preview(os.path.join(OUT, "preview_outfits_back.png"), shown, size=(1500, 900), camera_dir=(-0.5, -1.0, 0.35), margin=0.62, samples=32, background=(0.5, 0.55, 0.65))
print("OK", len(objects), "objects")
