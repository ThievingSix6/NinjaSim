"""Non-humanoid enemies, each piece centred on its rig part (see enemies.py for sizes).

Kitsune (beast rig):  FoxBody Fur Fluff, FoxHead Fur Fluff Nose Eyes, FoxLeg Fur Paw, FoxTail Fur Tip
Wisp:                 WispBody Flame (the core stays a neon part)
Golem:                GolemTorso Rock Glow, GolemHead Rock, GolemArm Rock, GolemFist Rock,
                      GolemBoulder Rock Glow, GolemLeg Rock
Training dummy:       Dummy Wood Straw Rope Face (built standing on its origin, scale 1)"""
import math
import random

import bmesh
import bpy
from mathutils import Vector
from mathutils.noise import noise as perlin

import common as C
import sculpt as S
from kit import M, almond, front_y, group, place
from shapes import swept, tube


def fluffy(depth=0.05, scale=5.0, locks=0.0, seed=0):
    """Fur: soft noise plus optional locks (ridges) running along the body."""
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))

    def fn(co, n):
        d = depth * perlin(co * scale + off)
        if locks:
            d += locks * max(0.0, math.sin(co.x * 14 + perlin(co * 2 + off) * 4)) * max(0.0, n.z)
        return d
    return fn


def tuft(name, base, tip, r, mat):
    return S.skin(name, [base, ((base[0] + tip[0]) / 2, (base[1] + tip[1]) / 2, (base[2] + tip[2]) / 2 + 0.03), tip], [(0, 1), (1, 2)], [r, r * 0.6, 0.01], M[mat], subdiv=1)


# ================================================================== kitsune: body 2.2 x 1.6 x 4, head 1.6 x 1.4 x 1.6, leg 0.6 x 1.6 x 0.6, tail 0.5 x 0.5 x 2
def fox():
    parts = [
        S.ellipsoid("chest", (0.82, 0.85, 0.72), (0, 1.0, 0.06), M["fur"]),
        S.ellipsoid("waist", (0.66, 1.1, 0.56), (0, -0.1, 0.08), M["fur"]),
        S.ellipsoid("haunch", (0.86, 0.8, 0.72), (0, -1.15, 0.04), M["fur"]),
        S.ellipsoid("neck", (0.48, 0.6, 0.55), (0, 1.72, 0.42), M["fur"], rot=(0.5, 0, 0)),
    ]
    for sx in (-1, 1):
        parts.append(S.ellipsoid("shoulder", (0.32, 0.45, 0.62), (sx * 0.62, 1.25, -0.35), M["fur"]))
        parts.append(S.ellipsoid("thigh", (0.38, 0.64, 0.72), (sx * 0.6, -1.25, -0.35), M["fur"]))
    body = S.fuse(parts, "foxBody", M["fur"], voxel=0.04, smooth=8)
    S.displace(body, fluffy(0.04, 4.0, 0.03, seed=1))
    body = group("FoxBody__Fur", [body], "fur", 5000)
    belly = S.extract(body, "belly", lambda c, n: n.z < -0.45 and abs(c.x) < 0.45 and c.y > -0.9, M["fluff"], offset=0.01, thick=0.03)
    ruff = [S.ellipsoid("ruff", (0.56, 0.42, 0.58), (0, 1.74, -0.06), M["fluff"])]
    for x in (-0.28, 0.0, 0.28):  # soft locks along the lower edge
        ruff.append(S.ellipsoid("lock", (0.16, 0.14, 0.26), (x, 1.9, -0.52 - 0.06 * (x == 0)), M["fluff"], rot=(0.4, 0, 0)))
    ruff = S.fuse(ruff, "ruff", M["fluff"], voxel=0.03, smooth=8)
    S.displace(ruff, lambda co, n: 0.03 * math.sin(math.atan2(co.x, co.z + 0.06) * 9))
    group("FoxBody__Fluff", [ruff, belly], "fluff", 3000)

    skull = S.ellipsoid("skull", (0.6, 0.6, 0.5), (0, -0.12, 0.1), M["fur"])
    snout = S.lofted("snout", [(0.15, 0.3, 0.26), (0.6, 0.22, 0.2), (1.02, 0.12, 0.11), (1.15, 0.05, 0.05)], M["fur"], power=2.2)
    snout.data.transform(__import__("mathutils").Matrix.Rotation(-math.pi / 2, 4, "X"))
    snout.data.transform(__import__("mathutils").Matrix.Translation((0, 0, -0.12)))
    ears = []
    for sx in (-1, 1):
        ears.append(S.skin("ear", [(sx * 0.34, -0.2, 0.42), (sx * 0.44, -0.22, 0.8), (sx * 0.52, -0.24, 1.2)], [(0, 1), (1, 2)], [(0.24, 0.12), (0.17, 0.08), (0.01, 0.01)], M["fur"], subdiv=2))
    head = S.fuse([skull, snout] + ears, "foxHead", M["fur"], voxel=0.025, smooth=5)
    S.displace(head, fluffy(0.02, 6.0, seed=2))
    head = group("FoxHead__Fur", [head], "fur", 4000)
    jaw = S.ellipsoid("jaw", (0.24, 0.5, 0.13), (0, 0.55, -0.3), M["fluff"])
    fluff = [jaw]
    for sx in (-1, 1):
        for j in range(3):  # cheek tufts sweeping back
            z = -0.1 - j * 0.12
            fluff.append(tuft("cheek", (sx * 0.4, 0.1, z), (sx * (0.82 - j * 0.06), -0.3, z - 0.18), 0.14, "fluff"))
        inner = S.skin("inner", [(sx * 0.36, -0.13, 0.5), (sx * 0.44, -0.14, 0.8), (sx * 0.5, -0.15, 1.08)], [(0, 1), (1, 2)], [(0.14, 0.04), (0.1, 0.03), (0.01, 0.01)], M["fluff"], subdiv=1)
        fluff.append(inner)
    group("FoxHead__Fluff", [S.fuse(fluff[:1] + fluff[1:], "foxFluff", M["fluff"], voxel=0.022, smooth=3)], "fluff", 2500)
    group("FoxHead__Nose", [S.ellipsoid("nose", (0.09, 0.07, 0.07), (0, 1.12, -0.07), M["dark"])], "dark")
    eyes = []
    for sx in (-1, 1):
        e = almond("eye", 0.12, 0.05, "eyes", sx, tilt=22, thick=0.05, angry=0.3)
        place(e, (sx * 0.3, front_y(head, sx * 0.3, 0.14) - 0.02, 0.14), (0, 0, math.radians(sx * -25)))
        eyes.append(e)
    group("FoxHead__Eyes", eyes, "eyes")

    leg = S.lofted("leg", [(-0.62, 0.14, 0.16), (-0.2, 0.17, 0.2), (0.2, 0.24, 0.3), (0.6, 0.34, 0.42), (0.9, 0.3, 0.36)], M["fur"], power=2.2)
    S.displace(leg, fluffy(0.015, 6.0, seed=3))
    group("FoxLeg__Fur", [S.subdivide(leg, 1)], "fur", 1500)
    paw = [S.ellipsoid("paw", (0.2, 0.28, 0.12), (0, 0.06, -0.72), M["fluff"], power=2.4)]
    paw += [S.ellipsoid("toe", (0.06, 0.08, 0.06), (x, 0.3, -0.76), M["fluff"]) for x in (-0.12, -0.04, 0.04, 0.12)]
    paw.append(S.lofted("sock", [(-0.7, 0.15, 0.17), (-0.4, 0.165, 0.185)], M["fluff"], power=2.2))
    group("FoxLeg__Paw", [S.fuse(paw, "paw", M["fluff"], voxel=0.018, smooth=3)], "fluff", 1200)

    def tail_part(name, y0, y1, r0, r1, mat, seed):
        blobs = []
        for i in range(9):
            t = i / 8
            y = y0 + (y1 - y0) * t
            r = r0 + (r1 - r0) * math.sin(t * math.pi * 0.9) if r1 > r0 else r0 + (r1 - r0) * t
            blobs.append(S.ellipsoid("b", (r, r * 1.3, r), (0, y, 0.12 * math.sin(t * 2)), M[mat]))
        o = S.fuse(blobs, name, M[mat], voxel=0.03, smooth=5)
        S.displace(o, lambda co, n: 0.05 * max(0.0, math.sin(math.atan2(co.z, co.x) * 7 + co.y * 3)) + 0.02 * perlin(co * 5 + Vector((seed, 0, 0))))
        return o
    group("FoxTail__Fur", [tail_part("tail", 1.0, -0.8, 0.16, 0.6, "fur", 1)], "fur", 3000)
    group("FoxTail__Tip", [tail_part("tip", -0.75, -1.65, 0.55, 0.06, "fluff", 2)], "fluff", 2000)


# ================================================================== wisp: body 2.2 ball
def wisp():
    parts = [S.ellipsoid("base", (1.0, 1.0, 0.95), (0, 0.05, -0.15), M["glow"])]
    tongues = [((0, -0.05, 0.3), (0, -0.75, 2.2), 0.85), ((0.5, 0.05, 0.25), (0.85, -0.55, 1.55), 0.5), ((-0.5, 0.05, 0.25), (-0.85, -0.6, 1.6), 0.5),
               ((0.3, 0.45, 0.2), (0.45, 0.1, 1.2), 0.38), ((-0.3, 0.45, 0.2), (-0.4, 0.05, 1.15), 0.38), ((0, -0.6, 0.0), (0, -1.9, 0.9), 0.55),
               ((0.45, -0.5, -0.1), (0.7, -1.8, 0.2), 0.4), ((-0.45, -0.5, -0.1), (-0.7, -1.8, 0.25), 0.4)]
    for base, tip, r in tongues:
        mid = ((base[0] * 0.6 + tip[0] * 0.4), (base[1] * 0.6 + tip[1] * 0.4) + 0.1, (base[2] * 0.6 + tip[2] * 0.4) + 0.1)
        parts.append(S.skin("tongue", [base, mid, tip], [(0, 1), (1, 2)], [r, r * 0.55, 0.015], M["glow"], subdiv=2))
    flame = S.fuse(parts, "wisp", M["glow"], voxel=0.04, smooth=4)
    S.displace(flame, lambda co, n: 0.05 * math.sin(co.z * 6 + math.atan2(co.x, -co.y) * 4) * max(0.0, co.z + 0.3) * 0.5)
    group("WispBody__Flame", [flame], "glow", 3000)


# ================================================================== golem: faceted rocks per rig part
def rock(name, half, center, seed, power=3.2, rough=0.12, segs=12, rings=8, rot=None):
    o = S.ellipsoid(name, half, center, M["rock"], power=power, segs=segs, rings=rings, rot=rot)
    rnd = random.Random(seed)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in bm.verts:
        k = 1 + rnd.uniform(-rough, rough)
        v.co = Vector(center) + (v.co - Vector(center)) * k
    bm.to_mesh(o.data)
    bm.free()
    for p in o.data.polygons:
        p.use_smooth = False
    return o


def flat(o):
    for p in o.data.polygons:
        p.use_smooth = False
    return o


def crack(name, target, pts2d, r=0.045):
    """Glowing vein across the front of `target`: (x, z) points projected onto its surface."""
    pts = [(x, front_y(target, x, z) - 0.015, z) for x, z in pts2d]
    return swept(name, pts, [r] * (len(pts) - 1) + [r * 0.3], M["glow"], n=6)


def golem():
    t = [
        rock("pecL", (0.8, 0.55, 0.62), (-0.74, 0.42, 0.58), 1),
        rock("pecR", (0.8, 0.55, 0.62), (0.74, 0.42, 0.58), 2),
        rock("belly", (0.95, 0.6, 0.55), (0, 0.3, -0.45), 3),
        rock("back", (1.4, 0.7, 1.1), (0, -0.3, 0.3), 4),
        rock("hip", (1.2, 0.8, 0.45), (0, 0.0, -1.12), 5),
        rock("shL", (0.7, 0.7, 0.66), (-1.18, 0.0, 0.88), 6),
        rock("shR", (0.7, 0.7, 0.66), (1.18, 0.0, 0.88), 7),
        rock("neck", (0.55, 0.5, 0.35), (0, -0.1, 1.36), 8),
    ]
    torso = group("GolemTorso__Rock", t, "rock")
    flat(torso)
    glow = [crack("c1", torso, [(0.02, 1.05), (-0.05, 0.75), (0.04, 0.45), (-0.02, 0.1), (0.05, -0.2)]),
            crack("c2", torso, [(-0.3, -0.3), (-0.55, -0.55), (-0.5, -0.8)], 0.035),
            crack("c3", torso, [(0.35, -0.2), (0.6, -0.5), (0.85, -0.55)], 0.035),
            crack("c4", torso, [(-0.9, 0.9), (-1.1, 0.6), (-1.05, 0.3)], 0.03)]
    gem = S.ellipsoid("core", (0.3, 0.16, 0.36), (0, front_y(torso, 0, 0.3) + 0.02, 0.3), M["glow"], power=1.2, segs=8, rings=6)
    group("GolemTorso__Glow", glow + [flat(gem)], "glow")
    h = [rock("skull", (0.6, 0.55, 0.52), (0, -0.05, 0.0), 11), rock("brow", (0.66, 0.22, 0.15), (0, 0.46, 0.3), 12, power=3.6),
         rock("jaw", (0.5, 0.36, 0.2), (0, 0.18, -0.42), 13)]
    flat(group("GolemHead__Rock", h, "rock"))
    a = [rock("a1", (0.62, 0.62, 0.55), (0, 0, 0.95), 21), rock("a2", (0.55, 0.55, 0.5), (0.02, 0.03, 0.05), 22), rock("a3", (0.5, 0.5, 0.45), (0, 0, -0.85), 23)]
    flat(group("GolemArm__Rock", a, "rock"))
    f = [rock("fist", (0.78, 0.78, 0.58), (0, 0, 0.05), 31)]
    f += [rock("knuckle", (0.2, 0.2, 0.2), (x, 0.62, -0.25), 32 + i, rough=0.18, segs=8, rings=6) for i, x in enumerate((-0.45, -0.15, 0.15, 0.45))]
    flat(group("GolemFist__Rock", f, "rock"))
    b = [rock("boulder", (0.88, 0.88, 0.68), (0, 0, 0), 41), rock("chip", (0.4, 0.4, 0.3), (0.45, -0.3, 0.55), 42)]
    flat(group("GolemBoulder__Rock", b, "rock"))
    crystals = []
    for i, (x, y, tilt) in enumerate(((-0.2, 0.1, -0.3), (0.15, -0.1, 0.2), (0.0, 0.35, 0.05))):
        c = S.ellipsoid("crystal", (0.13, 0.13, 0.42 - i * 0.08), (0, 0, 0), M["glow"], power=1.0, segs=6, rings=4)
        place(c, (x, y, 0.7 + (0.42 - i * 0.08) * 0.6), (tilt, tilt * 0.6, 0))
        crystals.append(flat(c))
    group("GolemBoulder__Glow", crystals, "glow")
    lg = [rock("thigh", (0.62, 0.62, 0.5), (0, 0, 0.4), 51), rock("foot", (0.66, 0.72, 0.4), (0, 0.1, -0.52), 52)]
    flat(group("GolemLeg__Rock", lg, "rock"))


# ================================================================== training dummy (standing on origin)
def dummy():
    base = C.lathe("base", [(0.0, 0.0), (1.3, 0.0), (1.34, 0.06), (1.34, 0.32), (1.26, 0.4), (0.0, 0.4)], 40, M["wood"], axis="Z")
    post = C.lathe("post", [(0.0, 0.38), (0.3, 0.38), (0.26, 0.6), (0.25, 5.3), (0.2, 5.4), (0.0, 5.42)], 20, M["wood"], axis="Z")
    bar = C.lathe("bar", [(0.0, -1.85), (0.17, -1.85), (0.21, -1.78), (0.2, 1.78), (0.17, 1.85), (0.0, 1.85)], 16, M["wood"], axis="Z")
    bar.data.transform(__import__("mathutils").Matrix.Rotation(math.pi / 2, 4, "Y"))
    bar.data.transform(__import__("mathutils").Matrix.Translation((0, 0, 4.1)))
    wood = [base, post, bar]
    for o in wood:
        S.displace(o, lambda co, n: 0.008 * math.sin(co.z * 40 + math.sin(co.x * 7) * 3))
    group("Dummy__Wood", wood, "wood", 3000)
    body = C.lathe("body", [(0.0, 2.5), (0.66, 2.54), (0.9, 2.8), (0.98, 3.6), (0.92, 4.35), (0.7, 4.62), (0.0, 4.66)], 64, M["straw"], axis="Z")
    body = S.subdivide(body, 1)
    S.displace(body, lambda co, n: 0.025 * math.sin(math.atan2(co.y, co.x) * 70 + co.z * 2) + 0.015 * perlin(co * 4))
    headball = S.ellipsoid("head", (0.66, 0.66, 0.7), (0, 0, 5.25), M["straw"], power=2.3, segs=48, rings=28)
    S.displace(headball, lambda co, n: 0.018 * math.sin(math.atan2(co.y, co.x) * 50 + (co.z - 5.25) * 3))
    face = []
    for sx in (-1, 1):  # stitched X eyes
        for ang in (45, -45):
            bar_ = C.box("x", (0.24, 0.04, 0.05), (0, 0, 0), M["dark"], bevel=0.012)
            place(bar_, (sx * 0.22, front_y(headball, sx * 0.22, 5.35) + 0.005, 5.35), (0, math.radians(ang), 0))
            face.append(bar_)
    mouth_pts = [(x, front_y(headball, x, 5.02 + 0.05 * (x / 0.25) ** 2) + 0.01, 5.02 + 0.05 * (x / 0.25) ** 2) for x in [(-0.25 + 0.5 * i / 8) for i in range(9)]]
    face.append(swept("mouth", mouth_pts, [0.02] * 9, M["dark"], n=6))
    for i in range(5):
        x = -0.2 + 0.1 * i
        z = 5.02 + 0.05 * (x / 0.25) ** 2
        st = C.box("stitch", (0.02, 0.03, 0.1), (0, 0, 0), M["dark"])
        place(st, (x, front_y(headball, x, z) + 0.01, z))
        face.append(st)
    rnd = random.Random(9)
    tufts = []
    for i in range(22):  # straw poking out under and over the bindings
        a = math.tau * i / 22 + rnd.uniform(-0.1, 0.1)
        z = 2.62 if i % 2 else 4.5
        r = 0.72 if i % 2 else 0.8
        tip_z = z - 0.25 if i % 2 else z + 0.2
        tufts.append(tuft("straw", (math.cos(a) * r, math.sin(a) * r, z), (math.cos(a) * (r + 0.28), math.sin(a) * (r + 0.28), tip_z), 0.05, "straw"))
    tufts.append(tuft("top", (0, 0, 5.85), (0.12, 0.05, 6.35), 0.12, "straw"))
    group("Dummy__Straw", [body, headball] + tufts, "straw", 6000)
    rope = []
    for z, r in ((2.85, 0.95), (3.6, 1.0), (4.35, 0.94), (4.74, 0.28)):
        for strand in range(2):
            pts = []
            for i in range(73):
                a = math.tau * i / 72
                tw = a * 14 + strand * math.pi
                pts.append((math.cos(a) * (r + 0.03 * math.cos(tw)), math.sin(a) * (r + 0.03 * math.cos(tw)), z + 0.035 * math.sin(tw)))
            rope.append(swept("rope", pts, [0.04] * 73, M["trim"], n=8))
    for sx in (-1, 1):
        rope.append(S.spiral_wrap("wrap", -0.14, 0.14, 0.22, 3, 0.07, 0.04, M["trim"], center=(0, 0), steps=40))
        rope[-1].data.transform(__import__("mathutils").Matrix.Rotation(math.pi / 2, 4, "Y"))
        rope[-1].data.transform(__import__("mathutils").Matrix.Translation((sx * 1.25, 0, 4.1)))
    group("Dummy__Rope", rope, "trim", 5000)
    group("Dummy__Face", face, "dark", 800)


def build():
    fox()
    wisp()
    golem()
    dummy()
