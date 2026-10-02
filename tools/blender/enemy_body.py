"""Sculpted enemy bodies for EnemyBuilder's R6-style rigs (see enemies.py for sizes).

Humanoid (gi):  EnemyTorso Cloth Skin Trim, EnemyHead Skin Brow Eyes Hair,
                EnemyArm Sleeve Skin Wrap, EnemyLeg Pants Wrap Boot
                (left-side mirrors: EnemyArmL Skin, EnemyLegL Boot, EnemyOniArmL Skin, EnemyOniLegL Skin)
Armour:         EnemyDo Plate Lace (cuirass + tassets), EnemySode Plate Lace (shoulders),
                EnemySuneate Plate (shins), EnemyMenpo Mask (face guard)
Oni:            EnemyOniTorso Skin Cloth Stripe Rope, EnemyOniHead Skin Fangs Hair Brow Eyes,
                EnemyOniArm Skin Cuff, EnemyOniLeg Skin Cuff
Every piece is centred on its rig part and faces Blender +Y (= Roblox -Z)."""
import math

import bpy

import common as C
import sculpt as S
from kit import M, almond, band_on, dent, front_y, group, mirrored, place
from shapes import ribbon, shell, swept, tube


# ================================================================== humanoid, gi-clad (torso 2 x 2 x 1.05)
def torso_shape(z):
    """Half width/depth of the gi torso at height z."""
    pts = [(-1.0, 0.86, 0.5), (-0.8, 0.9, 0.52), (-0.5, 0.84, 0.5), (-0.1, 0.88, 0.5), (0.35, 0.96, 0.52), (0.7, 0.98, 0.5), (0.86, 0.86, 0.44), (0.96, 0.58, 0.33), (1.0, 0.3, 0.26)]
    for (z0, x0, y0), (z1, x1, y1) in zip(pts, pts[1:]):
        if z <= z1:
            t = max(0.0, (z - z0) / (z1 - z0))
            return x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
    return pts[-1][1], pts[-1][2]


def torso():
    stations = [(-1.02, 0.84, 0.48), (-0.8, 0.9, 0.52), (-0.5, 0.84, 0.5), (-0.1, 0.88, 0.5), (0.35, 0.96, 0.52), (0.7, 0.98, 0.5), (0.86, 0.86, 0.44), (0.96, 0.58, 0.33), (1.0, 0.3, 0.26)]
    core = S.lofted("core", stations, M["cloth"], power=2.8)
    pecs = [S.ellipsoid("pec", (0.38, 0.15, 0.26), (sx * 0.32, 0.37, 0.42), M["cloth"]) for sx in (-1, 1)]
    delts = [S.ellipsoid("delt", (0.3, 0.36, 0.3), (sx * 0.84, 0.0, 0.66), M["cloth"]) for sx in (-1, 1)]
    lats = S.ellipsoid("lats", (0.82, 0.2, 0.44), (0, -0.3, 0.32), M["cloth"])
    neck = S.lofted("neck", [(0.86, 0.29, 0.27), (1.1, 0.27, 0.25)], M["cloth"])
    body = S.fuse([core, lats, neck] + pecs + delts, "etorso", M["cloth"], voxel=0.03, smooth=8)
    # cloth bunching under the belt and soft diagonal folds across the chest
    S.displace(body, lambda co, n: 0.02 * math.sin(co.x * 11 + co.z * 3) * max(0.0, 1 - abs(co.z + 0.72) / 0.28)
               + 0.012 * math.sin((co.x + co.z) * 9) * max(0.0, min(1.0, (co.z + 0.3) / 0.4)) * max(0.0, 1 - co.z))
    body = group("EnemyTorso__Cloth", [body], "cloth", 4500)
    # bare chest in the V between the lapels
    skin = S.extract(body, "vneck", lambda c, n: c.y > 0.15 and 0.2 < c.z < 1.0 and abs(c.x) < 0.36 * (c.z - 0.2) / 0.8 + 0.02, M["skin"], offset=0.006, thick=0.02)
    group("EnemyTorso__Skin", [skin], "skin", 1500)
    trim = []
    for side, bottom_x in ((-1, 0.3), (1, -0.3)):
        pts, normals = [], []
        for i in range(5):  # behind the neck, over the shoulder
            t = i / 4
            pts.append((side * (0.16 + 0.2 * t), -0.32 + 0.6 * t, 0.98 + 0.03 * math.sin(t * math.pi)))
            normals.append((0, -0.6 + 1.2 * t, 1.0))
        for i in range(1, 10):  # down across the chest to the belt
            t = i / 9
            pts.append((side * 0.36 + (bottom_x - side * 0.36) * t, 0.36 + 0.16 * t, 0.94 - 1.46 * t))
            normals.append((0, 1, 0.3 * (1 - t)))
        trim.append(band_on("lapel", pts, normals, 0.26, body, "trim", thick=0.05, offset=0.012 if side < 0 else 0.03))
    trim.append(tube("obi", [(-0.84, 0.93, 0.56), (-0.72, 0.945, 0.57), (-0.58, 0.93, 0.56)], M["trim"], n=48, power=2.8, thick=0.06))
    trim.append(S.ellipsoid("knot", (0.13, 0.08, 0.1), (0.42, 0.56, -0.7), M["trim"]))
    for dx, length in ((0.34, 0.5), (0.5, 0.42)):
        pts = [(dx + 0.03 * t, 0.58 + 0.03 * t, -0.74 - length * t) for t in [i / 6 for i in range(7)]]
        trim.append(ribbon("obiTail", pts, [(0, 1, 0)] * 7, [0.13 - 0.02 * (i / 6) for i in range(7)], 0.03, M["trim"]))
    group("EnemyTorso__Trim", trim, "trim", 3000)
    return body


# ------------------------------------------------------------------ head (1.25 cube)
EYE_Z = 0.04


def head_base(name="ehead", scale=1.0, brute=False):
    """Fused sculpted head: cranium, jaw, chin, brow ridge, cheekbones, nose and ears."""
    k = scale
    parts = [
        S.ellipsoid("cranium", (0.55 * k, 0.58 * k, 0.6 * k), (0, -0.04 * k, 0.05 * k), M["skin"], power=2.4),
        S.ellipsoid("jaw", ((0.5 if brute else 0.44) * k, 0.42 * k, 0.3 * k), (0, 0.1 * k, -0.3 * k), M["skin"], power=2.6),
        S.ellipsoid("chin", (0.2 * k, 0.13 * k, 0.12 * k), (0, 0.44 * k, -0.46 * k), M["skin"]),
        S.ellipsoid("brow", (0.44 * k, 0.12 * k, (0.12 if brute else 0.09) * k), (0, 0.49 * k, 0.17 * k), M["skin"]),
        S.ellipsoid("nose", ((0.13 if brute else 0.075) * k, 0.12 * k, (0.12 if brute else 0.15) * k), (0, 0.6 * k, -0.07 * k), M["skin"], rot=(-0.25, 0, 0)),
    ]
    for sx in (-1, 1):
        parts.append(S.ellipsoid("cheek", (0.15 * k, 0.12 * k, 0.12 * k), (sx * 0.3 * k, 0.43 * k, -0.06 * k), M["skin"]))
        if brute:  # pointed oni ears
            parts.append(S.ellipsoid("ear", (0.06 * k, 0.12 * k, 0.24 * k), (sx * 0.6 * k, -0.02 * k, 0.06 * k), M["skin"], rot=(0, math.radians(sx * -30), 0)))
            parts.append(S.ellipsoid("nostril", (0.07 * k, 0.07 * k, 0.06 * k), (sx * 0.11 * k, 0.62 * k, -0.15 * k), M["skin"]))
        else:
            parts.append(S.ellipsoid("ear", (0.06 * k, 0.12 * k, 0.17 * k), (sx * 0.55 * k, -0.02 * k, -0.02 * k), M["skin"]))
    body = S.fuse(parts, name, M["skin"], voxel=0.02 * k, smooth=6)
    # eye sockets under the brow
    S.displace(body, dent([(sx * 0.21 * k, 0.55 * k, EYE_Z * k) for sx in (-1, 1)], 0.16 * k, 0.05 * k))
    return body


def face_features(head, k, glare=0.5, brow_mat="dark", mouth_w=0.15, mouth=True):
    """Eyes (in the sockets), heavy angry brows and a grim mouth, placed on the surface."""
    eyes, brows = [], []
    for sx in (-1, 1):
        x = sx * 0.21 * k
        e = almond("eye", 0.1 * k, 0.05 * k, "eyes", sx, tilt=14, thick=0.05 * k, angry=glare)
        place(e, (x, front_y(head, x, EYE_Z * k) - 0.006 * k, EYE_Z * k))
        eyes.append(e)
        bz = EYE_Z * k + 0.11 * k
        b = S.ellipsoid("brow", (0.14 * k, 0.05 * k, 0.04 * k), (0, 0, 0), M[brow_mat], power=2.6, rot=(0, math.radians(sx * -22), 0))
        place(b, (sx * 0.2 * k, front_y(head, sx * 0.2 * k, bz) + 0.005 * k, bz))
        brows.append(b)
    if mouth:
        for sx in (-1, 1):  # two halves turned down at the corners: a frown
            mz = -0.28 * k
            m = S.ellipsoid("mouth", (mouth_w / 2 * k, 0.03 * k, 0.018 * k), (0, 0, 0), M[brow_mat], rot=(0, math.radians(sx * 10), 0))
            place(m, (sx * mouth_w / 2 * k * 0.9, front_y(head, sx * 0.07 * k, mz) - 0.01 * k, mz - 0.012 * k))
            brows.append(m)
    return eyes, brows


def head():
    body = head_base()
    body = group("EnemyHead__Skin", [body], "skin", 3000)
    eyes, brows = face_features(body, 1.0)
    group("EnemyHead__Eyes", eyes, "eyes")
    group("EnemyHead__Brow", brows, "dark", 800)
    # short spiky hair: a cap over the cranium, hairline higher at the front
    def keep(p):
        front = max(0.0, p.y) / 0.6
        return p.z > 0.05 + 0.25 * front and not (abs(p.x) > 0.5 and p.z < 0.2)
    hair = shell("hair", 0.62, (0.95, 1.0, 1.0), (0, -0.06, 0.07), keep, M["dark"], thick=0.05, segs=48, rings=30, power=2.4)
    hair = S.subdivide(hair, 1)
    S.displace(hair, lambda co, n: 0.05 * max(0.0, math.sin(math.atan2(co.x, -co.y) * 7) * math.sin(co.z * 9 + co.y * 6)) + 0.02)
    group("EnemyHead__Hair", [hair], "dark", 2000)


# ------------------------------------------------------------------ arm (0.9 x 2 x 0.9)
def fist(k=1.0, z=-0.84, mat="skin", thumb_side=-1):
    palm = S.ellipsoid("palm", (0.3 * k, 0.3 * k, 0.24 * k), (0, 0.03 * k, z), M[mat], power=3.0)
    knuckles = [S.ellipsoid("knuckle", (0.085 * k, 0.09 * k, 0.085 * k), (x * k, 0.28 * k, z + 0.07 * k), M[mat]) for x in (-0.18, -0.06, 0.06, 0.18)]
    thumb = S.ellipsoid("thumb", (0.09 * k, 0.17 * k, 0.09 * k), (thumb_side * 0.25 * k, 0.2 * k, z + 0.02 * k), M[mat], rot=(0.3, 0.0, thumb_side * -0.6))
    return [palm, thumb] + knuckles


def arm():
    sleeve = S.lofted("sleeve", [(-0.24, 0.12, 0.12), (-0.22, 0.34, 0.36), (-0.14, 0.42, 0.44), (0.3, 0.41, 0.42), (0.7, 0.4, 0.41), (0.9, 0.33, 0.34), (1.0, 0.15, 0.15)], M["cloth"], power=2.3, n=36)
    S.displace(sleeve, lambda co, n: 0.02 * math.sin(math.atan2(co.y, co.x) * 6 + co.z * 2) * max(0.0, min(1.0, (0.5 - co.z) / 0.6)))
    group("EnemyArm__Sleeve", [S.subdivide(sleeve, 1)], "cloth", 2200)
    fore = S.lofted("fore", [(-0.72, 0.25, 0.26), (-0.4, 0.28, 0.29), (0.0, 0.31, 0.32), (0.1, 0.3, 0.31)], M["skin"], power=2.2, n=28)
    skin = S.fuse([fore] + fist(), "earm", M["skin"], voxel=0.02, smooth=5)
    mirrored(group("EnemyArm__Skin", [skin], "skin", 2500), "EnemyArmL__Skin")
    wrap = S.spiral_wrap("wrap", -0.7, -0.3, 0.27, 3.5, 0.12, 0.03, M["wrap"], taper=-0.1, steps=80)
    group("EnemyArm__Wrap", [wrap], "trim", 900)


# ------------------------------------------------------------------ leg (0.95 x 2 x 0.95)
def tabi(k=1.0, z=-0.9, mat="dark"):
    body = S.ellipsoid("foot", (0.32 * k, 0.5 * k, 0.15 * k), (0, 0.16 * k, z), M[mat], power=2.6)
    big = S.ellipsoid("bigtoe", (0.1 * k, 0.14 * k, 0.11 * k), (-0.16 * k, 0.58 * k, z - 0.03 * k), M[mat])
    toes = S.ellipsoid("toes", (0.18 * k, 0.14 * k, 0.1 * k), (0.1 * k, 0.56 * k, z - 0.04 * k), M[mat])
    ankle = S.lofted("ankle", [(z, 0.28 * k, 0.28 * k), (z + 0.3 * k, 0.3 * k, 0.3 * k)], M[mat], power=2.2)
    return [body, big, toes, ankle]


def leg():
    pants = S.lofted("pants", [(-0.5, 0.12, 0.12), (-0.46, 0.4, 0.42), (-0.38, 0.5, 0.52), (0.0, 0.5, 0.52), (0.5, 0.5, 0.51), (0.9, 0.48, 0.5), (1.02, 0.42, 0.44)], M["cloth"], power=2.4, n=40)
    S.displace(pants, lambda co, n: 0.022 * math.sin(math.atan2(co.y, co.x) * 7) * max(0.0, min(1.0, (0.4 - co.z) / 0.6)))
    group("EnemyLeg__Pants", [S.subdivide(pants, 1)], "cloth", 2400)
    shin = S.lofted("shin", [(-0.8, 0.28, 0.29), (-0.5, 0.31, 0.32), (-0.3, 0.34, 0.35)], M["wrap"], power=2.2, n=28)
    wrap = S.spiral_wrap("wrap", -0.8, -0.34, 0.3, 4.0, 0.13, 0.03, M["wrap"], taper=-0.13, steps=90)
    group("EnemyLeg__Wrap", [shin, wrap], "wrap", 1600)
    boot = S.fuse(tabi(), "tabi", M["dark"], voxel=0.02, smooth=3)
    mirrored(group("EnemyLeg__Boot", [boot], "dark", 1500), "EnemyLegL__Boot")


# ================================================================== armour
def lames(prefix, top, count, step, height, shape, arc=None, power=3.0, out=0.08, flare=0.03, mat_plate="lacquer", knots=10):
    """Stacked armour lames (each flares a little) with a lacing strip and knots along the bottom."""
    plates, laces = [], []
    for i in range(count):
        zt = top - i * step
        hx, hy = shape(zt)
        hx, hy = hx + out, hy + out
        st = [(zt - height, hx + flare, hy + flare), (zt - height / 2, hx + flare * 0.6, hy + flare * 0.6), (zt, hx, hy)]
        plates.append(tube(prefix, st, M[mat_plate], n=56, power=power, thick=0.04, arc=arc))
        laces.append(tube(prefix + "Lace", [(zt - height - 0.015, hx + flare + 0.015, hy + flare + 0.015), (zt - height + 0.015, hx + flare + 0.013, hy + flare + 0.013)], M["trim"], n=56, power=power, thick=0.025, arc=arc))
        a0, a1 = arc if arc else (0.0, math.tau)
        for kk in range(knots):
            a = a0 + (a1 - a0) * (kk + 0.5 + 0.5 * (i % 2)) / (knots + (0 if arc else 0.0))
            if arc and not (a0 <= a <= a1):
                continue
            c, s = math.cos(a), math.sin(a)
            x = (hx + flare * 0.5 + 0.02) * math.copysign(abs(c) ** (2 / power), c)
            y = (hy + flare * 0.5 + 0.02) * math.copysign(abs(s) ** (2 / power), s)
            laces.append(S.ellipsoid("knot", (0.03, 0.03, 0.045), (x, y, zt - height / 2), M["trim"], segs=10, rings=6))
    return plates, laces


def armour(body):
    # do (cuirass): chest plates front and back, four laced lames, shoulder straps
    plates, laces = lames("do", 0.1, 4, 0.17, 0.21, torso_shape)
    hx, hy = torso_shape(0.35)
    for a0, a1 in ((20, 160), (200, 340)):
        arc = (math.radians(a0), math.radians(a1))
        plates.append(tube("mune", [(0.08, hx + 0.02, hy + 0.1), (0.35, hx + 0.08, hy + 0.12), (0.62, hx + 0.02, hy + 0.07)], M["lacquer"], n=36, power=2.8, thick=0.05, arc=arc))
        laces.append(tube("muneRim", [(0.59, hx + 0.035, hy + 0.09), (0.65, hx + 0.03, hy + 0.08)], M["trim"], n=36, power=2.8, thick=0.035, arc=arc))
    for sx in (-1, 1):
        pts = [(sx * 0.5, 0.62, 0.6), (sx * 0.52, 0.36, 0.9), (sx * 0.52, 0.0, 1.0), (sx * 0.52, -0.36, 0.9), (sx * 0.5, -0.62, 0.6)]
        nrm = [(0, 1, 0.4), (0, 0.6, 1), (0, 0, 1), (0, -0.6, 1), (0, -1, 0.4)]
        laces.append(band_on("watagami", pts, nrm, 0.22, body, "trim", thick=0.045, offset=0.05))
    # kusazuri (tassets): six hanging panels of three lames each, flaring over the legs
    def skirt(z):
        t = (-0.62 - z) / 0.7
        return 0.92 + 0.2 * t, 0.58 + 0.2 * t
    for k in range(6):
        c = 90 + k * 60
        arc = (math.radians(c - 26), math.radians(c + 26))
        p, l = lames("kusazuri", -0.62, 3, 0.2, 0.24, skirt, arc=arc, out=0.0, flare=0.04, knots=3)
        plates += p
        laces += l
    group("EnemyDo__Plate", plates, "lacquer", 5000)
    group("EnemyDo__Lace", laces, "trim", 4000)

    # sode: shoulder guards on the outer (+X) side of the arm
    sp, sl = [], []
    for i in range(4):
        top = 1.02 - i * 0.2
        r = 0.52 + i * 0.025
        arc = (math.radians(-70), math.radians(70))
        plate = tube("sode", [(top - 0.24, r + 0.05, r + 0.02), (top, r, r - 0.02)], M["lacquer"], n=24, power=2.4, thick=0.045, arc=arc)
        lace = tube("sodeLace", [(top - 0.255, r + 0.065, r + 0.035), (top - 0.225, r + 0.063, r + 0.033)], M["trim"], n=24, power=2.4, thick=0.025, arc=arc)
        for o in (plate, lace):
            place(o, (0.02, 0, 0), (0, math.radians(-8), 0))
        sp.append(plate)
        sl.append(lace)
    group("EnemySode__Plate", sp, "lacquer", 2000)
    group("EnemySode__Lace", sl, "trim", 1200)

    # suneate: splinted shin guard and knee cap on the lower leg
    base = S.lofted("tmp", [(-0.84, 0.36, 0.37), (-0.55, 0.39, 0.4), (-0.3, 0.42, 0.43)], M["metal"], power=2.2, n=40, caps=False)
    base = S.subdivide(base, 2)
    guard = S.extract(base, "suneate", lambda c, n: c.y > 0.1 and -0.82 < c.z < -0.3, M["lacquer"], offset=0.02, thick=0.045)
    bpy.data.objects.remove(base)
    splints = [S.ellipsoid("splint", (0.035, 0.03, 0.22), (x, front_y(guard, x, -0.56) + 0.01, -0.56), M["lacquer"]) for x in (-0.18, 0.0, 0.18)]
    knee = S.ellipsoid("knee", (0.24, 0.1, 0.18), (0, 0.5, -0.2), M["lacquer"], power=2.4)
    group("EnemySuneate__Plate", [guard, knee] + splints, "lacquer", 1600)


def menpo():
    """Samurai face guard: nose to chin, snarling moustache and a laced throat guard."""
    ref = head_base("menpoRef")
    mask = S.extract(ref, "menpo", lambda c, n: c.y > 0.15 and c.z < -0.06, M["lacquer"], offset=0.035, thick=0.04)
    stache = []
    for sx in (-1, 1):
        pts = [(sx * (0.02 + 0.3 * t), front_y(mask, sx * 0.02, -0.2) + 0.02 - 0.12 * t * t, -0.19 - 0.08 * t + 0.1 * t * t) for t in [i / 7 for i in range(8)]]
        stache.append(ribbon("stache", pts, [(0, 1, 0.2)] * 8, [0.07 * (1 - 0.7 * i / 7) for i in range(8)], 0.03, M["dark"]))
    throat = []
    for i in range(3):
        top = -0.56 - i * 0.12
        throat.append(tube("yodare", [(top - 0.14, 0.5 + 0.04 * i, 0.52 + 0.04 * i), (top, 0.45 + 0.04 * i, 0.47 + 0.04 * i)], M["lacquer"], n=32, power=2.4, thick=0.035, arc=(math.radians(15), math.radians(165))))
    bpy.data.objects.remove(ref)
    group("EnemyMenpo__Mask", [mask] + throat, "lacquer", 2500)
    group("EnemyMenpo__Stache", stache, "dark", 600)


# ================================================================== oni (torso 2.6 x 2.3 x 1.05, head 1.5, arm 1.15 x 2.3, leg 1.15 x 2)
def oni_torso():
    core = S.lofted("core", [(-1.15, 1.02, 0.6), (-0.8, 1.1, 0.72), (-0.3, 1.08, 0.74), (0.2, 1.14, 0.68), (0.6, 1.24, 0.64), (0.92, 1.1, 0.56), (1.08, 0.7, 0.42), (1.16, 0.4, 0.34)], M["skin"], power=2.6)
    parts = [core,
             S.ellipsoid("belly", (0.8, 0.42, 0.6), (0, 0.4, -0.45), M["skin"]),
             S.ellipsoid("lats", (1.12, 0.3, 0.6), (0, -0.36, 0.3), M["skin"]),
             S.ellipsoid("traps", (0.62, 0.3, 0.3), (0, -0.1, 0.92), M["skin"])]
    for sx in (-1, 1):
        parts.append(S.ellipsoid("pec", (0.5, 0.2, 0.34), (sx * 0.44, 0.5, 0.48), M["skin"], rot=(0, math.radians(sx * 10), 0)))
        parts.append(S.ellipsoid("delt", (0.42, 0.46, 0.4), (sx * 1.08, 0.0, 0.76), M["skin"]))
        parts.append(S.ellipsoid("oblique", (0.24, 0.4, 0.5), (sx * 0.9, 0.12, -0.35), M["skin"]))
        for row in range(2):  # upper abs above the belly
            parts.append(S.ellipsoid("ab", (0.17, 0.1, 0.12), (sx * 0.19, 0.64, 0.02 - row * 0.24), M["skin"]))
    body = S.fuse(parts, "oniTorso", M["skin"], voxel=0.035, smooth=8)
    S.displace(body, dent([(0, 0.8, -0.5)], 0.08, 0.05))  # navel
    body = group("EnemyOniTorso__Skin", [body], "skin", 5000)
    # tiger-skin loincloth: hip wrap plus front and back flaps
    wrap = tube("hipwrap", [(-1.2, 1.12, 0.78), (-0.98, 1.1, 0.77), (-0.72, 1.08, 0.76)], M["cloth"], n=56, power=2.6, thick=0.08)
    S.displace(wrap, lambda co, n: 0.03 * math.sin(math.atan2(co.y, co.x) * 9) * max(0.0, (-0.8 - co.z) / 0.4))
    flaps = []
    for y, sgn in ((0.82, 1), (-0.8, -1)):
        pts = [(0, y + sgn * 0.03 * t, -0.85 - 0.8 * t) for t in [i / 6 for i in range(7)]]
        flaps.append(ribbon("flap", pts, [(0, sgn, 0)] * 7, [0.8 - 0.25 * (i / 6) for i in range(7)], 0.05, M["cloth"]))
    loin = S.subdivide(C.merge([wrap] + flaps, "loin", M["cloth"]), 2)
    loin = group("EnemyOniTorso__Cloth", [loin], "cloth", 5000)
    # stripes: thin dark bands pulled off the loincloth
    stripe = S.extract(loin, "stripe", lambda c, n: math.sin(c.x * 6 + c.z * 5 + 0.8 * math.sin(c.y * 5)) > 0.7, M["dark"], offset=0.006, thick=0.012)
    group("EnemyOniTorso__Stripe", [stripe], "dark", 2500)
    # shimenawa rope belt with a knot and tassels at the front
    twist = []
    for strand in range(2):
        pts, radii = [], []
        for i in range(97):
            t = i / 96
            a = math.tau * t
            tw = a * 9 + strand * math.pi
            x = math.copysign(abs(math.cos(a)) ** (2 / 2.6), math.cos(a)) * 1.2
            y = math.copysign(abs(math.sin(a)) ** (2 / 2.6), math.sin(a)) * 0.86
            pts.append((x + 0.05 * math.cos(tw) * math.cos(a), y + 0.05 * math.cos(tw) * math.sin(a), -0.7 + 0.05 * math.sin(tw)))
            radii.append(0.075)
        twist.append(swept("rope", pts, radii, M["straw"], n=10))
    knot = S.ellipsoid("ropeKnot", (0.2, 0.14, 0.16), (0.0, 0.92, -0.72), M["straw"])
    tassels = [S.ellipsoid("tassel", (0.07, 0.06, 0.22), (sx * 0.12, 0.93, -0.98), M["straw"]) for sx in (-1, 1)]
    group("EnemyOniTorso__Rope", twist + [knot] + tassels, "straw", 3000)


def oni_head():
    k = 1.2  # head 1.5 = 1.25 * 1.2
    body = head_base("oniHead", k, brute=True)
    S.displace(body, lambda co, n: 0.02 * math.sin(co.x * 20) * max(0.0, 1 - abs(co.z - 0.3 * k) / 0.12) * max(0.0, co.y))  # furrowed brow
    body = group("EnemyOniHead__Skin", [body], "skin", 3500)
    eyes, brows = face_features(body, k, glare=0.6, mouth_w=0.36)
    group("EnemyOniHead__Eyes", eyes, "eyes")
    # bushy brows as thick clumps
    for sx in (-1, 1):
        for j in range(3):
            x = sx * (0.1 + j * 0.1) * k
            z = (EYE_Z + 0.15 + j * 0.03) * k
            b = S.ellipsoid("bushy", (0.08 * k, 0.07 * k, 0.06 * k), (x, front_y(body, x, z) + 0.01, z), M["dark"], rot=(0, math.radians(sx * -25), 0))
            brows.append(b)
    group("EnemyOniHead__Brow", brows, "dark", 1200)
    fangs = []
    for sx in (-1, 1):  # tusks from the lower jaw
        base_y = front_y(body, sx * 0.2 * k, -0.34 * k)
        fangs.append(S.skin("tusk", [(sx * 0.2 * k, base_y - 0.04, -0.34 * k), (sx * 0.22 * k, base_y + 0.03, -0.18 * k), (sx * 0.26 * k, base_y + 0.02, -0.06 * k)], [(0, 1), (1, 2)], [0.06 * k, 0.04 * k, 0.008], M["bone"], subdiv=2))
        for j in range(2):
            x = sx * (0.05 + j * 0.07) * k
            fangs.append(S.ellipsoid("tooth", (0.03 * k, 0.02 * k, 0.04 * k), (x, front_y(body, x, -0.3 * k) - 0.005, -0.3 * k), M["bone"]))
    group("EnemyOniHead__Fangs", fangs, "bone", 1200)
    # wild mane: clumps swept back from the crown
    clumps = []
    for i in range(22):
        a = math.radians(-100 + (i % 11) * 20)
        row = i // 11
        z0 = (0.42 - row * 0.28) * k
        base = (math.sin(a) * 0.5 * k, -math.cos(a) * 0.45 * k - 0.1 * k, z0)
        tip = (base[0] * 1.5, base[1] - 0.5 * k - row * 0.1, z0 - 0.25 * k - row * 0.2)
        mid = ((base[0] + tip[0]) / 2, (base[1] + tip[1]) / 2 + 0.05, (base[2] + tip[2]) / 2 + 0.12)
        if math.cos(a) < -0.3 and row == 0:  # keep the forehead clear
            continue
        clumps.append(S.skin("clump", [base, mid, tip], [(0, 1), (1, 2)], [0.2 * k, 0.14 * k, 0.02], M["dark"], subdiv=2))
    group("EnemyOniHead__Hair", clumps, "dark", 4000)


def oni_arm():
    parts = [
        S.lofted("upper", [(0.0, 0.42, 0.44), (0.5, 0.5, 0.52), (1.0, 0.46, 0.46)], M["skin"], power=2.2),
        S.ellipsoid("bicep", (0.34, 0.3, 0.44), (0.0, 0.2, 0.48), M["skin"]),
        S.ellipsoid("delt", (0.52, 0.5, 0.42), (0.08, 0.0, 0.92), M["skin"]),
        S.lofted("fore", [(-0.95, 0.36, 0.38), (-0.45, 0.44, 0.46), (0.0, 0.46, 0.46), (0.1, 0.42, 0.42)], M["skin"], power=2.2),
    ] + fist(1.45, z=-1.12)
    body = S.fuse(parts, "oniArm", M["skin"], voxel=0.03, smooth=7)
    mirrored(group("EnemyOniArm__Skin", [body], "skin", 3500), "EnemyOniArmL__Skin")
    cuff = tube("cuff", [(-0.9, 0.47, 0.49), (-0.62, 0.5, 0.52)], M["metal"], n=36, power=2.4, thick=0.06)
    spikes = []
    for kk in range(8):
        a = math.tau * kk / 8
        sp = S.skin("spike", [(0, 0, 0), (0.16, 0, 0)], [(0, 1)], [0.06, 0.004], M["metal"], subdiv=1)
        place(sp, (math.cos(a) * 0.52, math.sin(a) * 0.54, -0.76), (0, 0, a))
        spikes.append(sp)
    group("EnemyOniArm__Cuff", [cuff] + spikes, "metal", 1500)


def oni_leg():
    parts = [
        S.lofted("thigh", [(-0.1, 0.44, 0.48), (0.4, 0.54, 0.58), (1.0, 0.56, 0.6)], M["skin"], power=2.3),
        S.ellipsoid("knee", (0.26, 0.2, 0.22), (0, 0.3, -0.12), M["skin"]),
        S.lofted("calf", [(-0.78, 0.34, 0.36), (-0.4, 0.42, 0.46), (-0.1, 0.44, 0.48)], M["skin"], power=2.3),
        S.ellipsoid("calfBulge", (0.3, 0.26, 0.3), (0, -0.2, -0.4), M["skin"]),
        S.ellipsoid("foot", (0.38, 0.6, 0.18), (0, 0.2, -0.9), M["skin"], power=2.6),
    ]
    for kk, x in enumerate((-0.22, -0.07, 0.08, 0.22)):
        parts.append(S.ellipsoid("toe", (0.08 - 0.01 * (kk > 0), 0.1, 0.08), (x, 0.74, -0.95), M["skin"]))
    body = S.fuse(parts, "oniLeg", M["skin"], voxel=0.03, smooth=6)
    mirrored(group("EnemyOniLeg__Skin", [body], "skin", 3000), "EnemyOniLegL__Skin")
    cuff = tube("anklet", [(-0.74, 0.4, 0.42), (-0.6, 0.42, 0.44)], M["metal"], n=36, power=2.4, thick=0.05)
    group("EnemyOniLeg__Cuff", [cuff], "metal", 600)


def build():
    body = torso()
    head()
    arm()
    leg()
    armour(body)
    menpo()
    oni_torso()
    oni_head()
    oni_arm()
    oni_leg()
