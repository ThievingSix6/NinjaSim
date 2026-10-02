"""NinjaSim enemy pack (v2, sculpted). Pieces are centred on the EnemyBuilder rig part
they dress, facing Blender +Y (= Roblox -Z), and the game scales each one by
(part size / reference size):

  humanoid  torso 2 x 2 x 1.05, head 1.25, arm 0.9 x 2 x 0.9, leg 0.95 x 2 x 0.95
  oni       torso 2.6 x 2.3 x 1.05, head 1.5, arm 1.15 x 2.3 x 1.15, leg 1.15 x 2 x 1.15
  hats      head 1.25 (EnemyHat_*, EnemyHorns); claws use the humanoid arm
  kitsune   body 2.2 x 1.6 x 4, head 1.6 x 1.4 x 1.6, leg 0.6 x 1.6 x 0.6, tail 0.5 x 0.5 x 2
  golem     torso 3.2 x 3 x 2, head 1.4 x 1.2 x 1.3, arm 1.4 x 3 x 1.4, fist 1.7 x 1.3 x 1.7,
            boulder 1.8 x 1.4 x 1.8, leg 1.3 x 1.8 x 1.3
  wisp      body 2.2 ball
Weapons start at the grip and point forward; the dummy stands on its origin at scale 1.
Modules: enemy_body.py (bodies, armour, oni), enemy_gear.py (hats, weapons),
enemy_beasts.py (kitsune, wisp, golem, dummy).

Run: python3 tools/blender/enemies.py <out_dir> [body,gear,beasts]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
from mathutils import Matrix  # noqa: E402

import common as C  # noqa: E402
import sculpt as S  # noqa: E402
from common import rgb  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/enemies"
os.makedirs(OUT, exist_ok=True)
C.reset_scene()

import enemy_beasts  # noqa: E402
import enemy_body  # noqa: E402
import enemy_gear  # noqa: E402
from kit import objects  # noqa: E402

only = set(sys.argv[2].split(",")) if len(sys.argv) > 2 else {"body", "gear", "beasts"}
if "body" in only:
    enemy_body.build()
if "gear" in only:
    enemy_gear.build()
if "beasts" in only:
    enemy_beasts.build()

C.write_manifest(os.path.join(OUT, "EnemyManifest.lua"), "enemies.py", objects, "rig pieces are centred on the part they dress; weapons start at the grip; the dummy stands on its origin")
C.export_fbx(os.path.join(OUT, "NinjaSim_Enemies.fbx"), objects)
print("TRIS", sum(S.tris(o) for o in objects), {o.name: S.tris(o) for o in objects})

# ================================================================== preview line-ups
by = {o.name: o for o in objects}
shown = []
_mats = {}


def mat(color, glow=False, metal=False):
    key = (tuple(color), glow, metal)
    if key not in _mats:
        _mats[key] = C.material("p%d" % len(_mats), color, metallic=0.6 if metal else 0.0, roughness=0.35 if metal else 0.8,
                                emission=color if glow else None, strength=4.0 if glow else 1.0)
    return _mats[key]


def put(name, loc, scale=(1, 1, 1), material=None, rot=None):
    if name not in by:
        return None
    d = by[name].copy()
    d.data = by[name].data.copy()
    bpy.context.scene.collection.objects.link(d)
    if material is not None:
        d.data.materials.clear()
        d.data.materials.append(material)
    if rot is not None:
        d.data.transform(rot)
    d.data.transform(Matrix.Diagonal((*scale, 1.0)))
    d.location = loc
    shown.append(d)
    return d


DARK = rgb(34, 28, 30)
BONE = rgb(245, 240, 225)


def humanoid(x, col, hat=None, weapon=None, s=1.0, oni=False, armour=None, menpo=False, glow=False, hair=True):
    body, clothes, accent, skin, eyes = col
    tw, th, aw, al, lw, hs = (2.6, 2.3, 1.15, 2.3, 1.15, 1.5) if oni else (2.0, 2.0, 0.9, 2.0, 0.95, 1.25)
    ty = 2 * s + th * s / 2
    hz = ty + th * s / 2 + hs * s / 2
    arm_z = ty + th * s / 2 - 0.25 * s - (al * s / 2 - 0.25 * s)
    k = (s, s, s)
    eye_mat = mat(eyes, glow=glow)
    if oni:
        put("EnemyOniTorso__Skin", (x, 0, ty), k, mat(skin))
        put("EnemyOniTorso__Cloth", (x, 0, ty), k, mat(clothes))
        put("EnemyOniTorso__Stripe", (x, 0, ty), k, mat(DARK))
        put("EnemyOniTorso__Rope", (x, 0, ty), k, mat(rgb(225, 205, 150)))
        put("EnemyOniHead__Skin", (x, 0, hz), k, mat(skin))
        put("EnemyOniHead__Eyes", (x, 0, hz), k, eye_mat)
        put("EnemyOniHead__Brow", (x, 0, hz), k, mat(DARK))
        put("EnemyOniHead__Fangs", (x, 0, hz), k, mat(BONE))
        put("EnemyOniHead__Hair", (x, 0, hz), k, mat(DARK))
        for sx in (-1, 1):
            L = "L" if sx < 0 else ""
            put("EnemyOniArm%s__Skin" % L, (x + sx * (tw + aw) * s / 2, 0, arm_z), k, mat(skin))
            put("EnemyOniArm__Cuff", (x + sx * (tw + aw) * s / 2, 0, arm_z), k, mat(rgb(60, 60, 66), metal=True))
            put("EnemyOniLeg%s__Skin" % L, (x + sx * tw * s / 4, 0, s), k, mat(skin))
            put("EnemyOniLeg__Cuff", (x + sx * tw * s / 4, 0, s), k, mat(rgb(60, 60, 66), metal=True))
        hat_scale = hs / 1.25 * s
    else:
        put("EnemyTorso__Cloth", (x, 0, ty), k, mat(clothes))
        put("EnemyTorso__Skin", (x, 0, ty), k, mat(skin))
        put("EnemyTorso__Trim", (x, 0, ty), k, mat(accent))
        put("EnemyHead__Skin", (x, 0, hz), k, mat(skin))
        put("EnemyHead__Eyes", (x, 0, hz), k, eye_mat)
        put("EnemyHead__Brow", (x, 0, hz), k, mat(DARK))
        if hair:
            put("EnemyHead__Hair", (x, 0, hz), k, mat(DARK))
        for sx in (-1, 1):
            ax = x + sx * (tw + aw) * s / 2
            put("EnemyArm__Sleeve", (ax, 0, arm_z), k, mat(clothes))
            put("EnemyArm%s__Skin" % ("L" if sx < 0 else ""), (ax, 0, arm_z), k, mat(skin))
            put("EnemyArm__Wrap", (ax, 0, arm_z), k, mat(accent))
            lx = x + sx * tw * s / 4
            put("EnemyLeg__Pants", (lx, 0, s), k, mat(clothes))
            put("EnemyLeg__Wrap", (lx, 0, s), k, mat([c * 0.5 + 110 / 255 for c in clothes]))
            put("EnemyLeg%s__Boot" % ("L" if sx < 0 else ""), (lx, 0, s), k, mat(DARK))
            if armour:
                put("EnemySuneate__Plate", (lx, 0, s), k, mat(body, metal=True))
                if armour == "Full":
                    rot = Matrix.Rotation(math.pi, 4, "Z") if sx < 0 else None
                    put("EnemySode__Plate", (ax, 0, arm_z), k, mat(body, metal=True), rot)
                    put("EnemySode__Lace", (ax, 0, arm_z), k, mat(accent), rot)
        if armour:
            put("EnemyDo__Plate", (x, 0, ty), k, mat(body, metal=True))
            put("EnemyDo__Lace", (x, 0, ty), k, mat(accent))
        if menpo:
            put("EnemyMenpo__Mask", (x, 0, hz), k, mat(body, metal=True))
            put("EnemyMenpo__Stache", (x, 0, hz), k, mat(DARK))
        hat_scale = s
    if hat:
        hk = (hat_scale,) * 3
        colors = {"Straw": rgb(214, 186, 120), "Band": accent, "Metal": body, "Crest": accent, "Lace": accent, "Horn": BONE,
                  "Gold": accent, "Gems": accent, "Cloth": accent, "Hair": DARK}
        for name in [n for n in by if n.startswith(hat + "__")]:
            part = name.split("__")[1]
            put(name, (x, 0, hz), hk, mat(colors.get(part, accent), glow=part == "Gems", metal=part in ("Metal", "Gold", "Crest")))
    if weapon:
        ax = x + (tw + aw) * s / 2
        hand = (ax, 0.0, arm_z - al * s / 2 + 0.2 * s)
        rot = Matrix.Rotation(math.radians(-10), 4, "X")
        colors = {"Wood": rgb(70, 50, 40), "Grip": accent, "Studs": rgb(200, 200, 205), "Shaft": rgb(110, 80, 50), "Blade": rgb(220, 220, 230),
                  "Tassel": accent, "Metal": rgb(230, 190, 90), "Orb": accent}
        for name in [n for n in by if n.startswith(weapon + "__")]:
            part = name.split("__")[1]
            put(name, hand, k, mat(colors.get(part, accent), glow=part == "Orb", metal=part in ("Blade", "Studs", "Metal")), rot)
    if weapon is None and not oni and "EnemyClaw__Blade" in by and hat == "EnemyHorns":
        for sx in (-1, 1):
            ax = x + sx * (tw + aw) * s / 2
            put("EnemyClaw%s__Blade" % ("L" if sx < 0 else ""), (ax, 0, arm_z), k, mat(accent, glow=glow))
            put("EnemyClaw__Band", (ax, 0, arm_z), k, mat(DARK))


def finish(path, size, camera_dir, margin, width):
    C.apply_transforms(shown)
    ground = C.box("ground", (width, 14, 0.2), (0, 0, -0.1), C.material("Floor", rgb(70, 80, 70), roughness=1))
    shown.append(ground)
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = o not in shown
    C.render_preview(path, shown, size=size, camera_dir=camera_dir, margin=margin, samples=40, background=(0.5, 0.55, 0.65))


if "body" in only:
    # (body, clothes, accent, skin, eyes) as in Config/Enemies.lua
    humanoid(-15, (rgb(150, 110, 70), rgb(110, 70, 40), rgb(200, 60, 40), rgb(210, 160, 120), rgb(20, 20, 20)), "EnemyHat_Bandana", "EnemyKanabo", 1.1)
    humanoid(-10, (rgb(90, 70, 50), rgb(160, 40, 40), rgb(30, 30, 30), rgb(225, 185, 145), rgb(20, 20, 20)), "EnemyHat_Kasa", "EnemyYari", 1.05, armour="Light")
    humanoid(-5, (rgb(170, 40, 40), rgb(40, 30, 30), rgb(230, 190, 80), rgb(225, 185, 145), rgb(255, 80, 40)), "EnemyHat_Kabuto", None, 1.25, armour="Full", menpo=True, glow=True, hair=False)
    humanoid(0, (rgb(240, 240, 250), rgb(255, 200, 80), rgb(120, 200, 255), rgb(235, 200, 170), rgb(40, 60, 90)), "EnemyHat_Topknot", "EnemyStaff", 1.05, hair=False)
    humanoid(5, (rgb(120, 200, 80), rgb(70, 140, 50), rgb(250, 240, 90), rgb(140, 220, 90), rgb(255, 60, 60)), "EnemyHorns", None, 1.2, glow=True)
    humanoid(11.5, (rgb(50, 90, 170), rgb(230, 200, 60), rgb(240, 240, 230), rgb(50, 90, 170), rgb(255, 255, 120)), "EnemyHorns", "EnemyKanabo", 1.3, oni=True, glow=True)
    finish(os.path.join(OUT, "preview_enemies.png"), (2000, 900), (0.2, 1.0, 0.25), 0.8, 40)
    for o in list(shown):
        bpy.data.objects.remove(o)
    shown.clear()

if "beasts" in only:
    fx, fz = -9.0, 1.6 + 0.8
    fox = {"Fur": rgb(230, 130, 50), "Fluff": rgb(255, 250, 240), "Nose": DARK, "Eyes": rgb(255, 220, 90), "Paw": rgb(255, 250, 240), "Tip": rgb(255, 250, 240)}
    for name in ("FoxBody__Fur", "FoxBody__Fluff"):
        put(name, (fx, 0, fz), material=mat(fox[name.split("__")[1]]))
    for name in ("FoxHead__Fur", "FoxHead__Fluff", "FoxHead__Nose", "FoxHead__Eyes"):
        put(name, (fx, 2.6, fz + 0.72), material=mat(fox[name.split("__")[1]], glow=name.endswith("Eyes")))
    for lx, ly in ((0.77, 1.4), (-0.77, 1.4), (0.77, -1.4), (-0.77, -1.4)):
        put("FoxLeg__Fur", (fx + lx, ly, 0.8), material=mat(fox["Fur"]))
        put("FoxLeg__Paw", (fx + lx, ly, 0.8), material=mat(fox["Paw"]))
    for name in ("FoxTail__Fur", "FoxTail__Tip"):
        # tail part hangs 1 stud behind its hinge on the rump, raised 35 degrees
        put(name, (fx, -2.0, fz + 0.48), material=mat(fox[name.split("__")[1]]),
            rot=Matrix.Rotation(math.radians(-35), 4, "X") @ Matrix.Translation((0, -1.0, 0)))
    # golem (scale 1): torso centre at leg length + half torso height
    gx, gz = -1.0, 1.8 + 1.5
    rock, glow = mat(rgb(60, 50, 48)), mat(rgb(255, 110, 20), glow=True)
    put("GolemTorso__Rock", (gx, 0, gz), material=rock)
    put("GolemTorso__Glow", (gx, 0, gz), material=glow)
    put("GolemHead__Rock", (gx, 0.3, gz + 1.9), material=rock)
    for eye_x in (-0.3, 0.3):
        shown.append(C.box("eye", (0.22, 0.06, 0.16), (gx + eye_x, 0.97, gz + 1.95), glow))
    for sx in (-1, 1):
        ax = gx + sx * 2.35
        put("GolemArm__Rock", (ax, 0, gz + 0.6), material=rock)
        put("GolemFist__Rock", (ax, 0, gz - 0.9), material=rock)
        put("GolemBoulder__Rock", (ax, 0, gz + 1.9), material=rock)
        put("GolemBoulder__Glow", (ax, 0, gz + 1.9), material=glow)
        put("GolemLeg__Rock", (gx + sx * 0.9, 0, 0.9), material=rock)
    put("WispBody__Flame", (6.0, 0, 4.1), material=mat(rgb(170, 90, 255), glow=True))
    for name, c in (("Dummy__Wood", rgb(110, 76, 48)), ("Dummy__Straw", rgb(214, 180, 120)), ("Dummy__Rope", rgb(120, 80, 50)), ("Dummy__Face", DARK)):
        put(name, (12.0, 0, 0), material=mat(c))
    finish(os.path.join(OUT, "preview_beasts.png"), (1800, 800), (0.35, 1.0, 0.3), 0.85, 34)
print("OK", len(objects), "objects")
