"""Demonic enemies in the style of the hero ninja suits (hero_ninjas.py).

Enemies use an R6-style rig (Torso, Head, Right/Left Arm, Right/Left Leg; see
Visuals/EnemyBuilder.lua), so each variant is built in the same R6 layout as the
ninja suits (torso 2x2x1 on the origin, facing Blender +Y, its right side at +X),
baked into ONE texture (assets/textures/HeroDemon_<variant>.png, colour x AO) and cut
into one mesh per R6 part: HeroDemon_<variant>_<Part> (Head, Torso, RightArm,
LeftArm, RightLeg, LeftLeg) plus HeroDemon_<variant>_<Part>__Glow for the neon bits
(eyes, cracks, sigils), which the game colours with the enemy's eye colour.

Every piece is exported centred on its part and stretched to DEMON_REF (EnemyBuilder),
so the game scales it onto any enemy's parts (bigger for oni, smaller for imps).

Families (body builds), each with several palettes:
  hood     hooded demon ninja: horns through the hood, glowing slit eyes, a fanged
           mask, claws, spiked shoulder, torn cloth tails
  samurai  armoured demon: horned kabuto, fanged menpo, chest plate, shoulder and
           hip plates, shin guards
  oni      bare-chested brute: muscles, huge horns, tusks, mane, tiger loincloth,
           spiked bracers, clawed feet
  imp      small hoodless devil: bald head, big horns, tail, loincloth

Run: python3 tools/blender/hero_demons.py <out_dir> [variants...]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import bake  # noqa: E402
import common as C  # noqa: E402
import hero as H  # noqa: E402
import hero_ninjas as N  # noqa: E402
import sculpt as S  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/hero_demons"
ONLY = sys.argv[2:]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX = os.path.join(ROOT, "assets", "textures")
PREV = os.path.join(ROOT, "assets", "previews", "demons")
for d in (OUT, TEX, PREV):
    os.makedirs(d, exist_ok=True)

# R6 part -> (centre, size in the layout, exported size = DEMON_REF in EnemyBuilder)
PARTS = {
    "Head": ((0, 0, 1.6), (1.2, 1.2, 1.2), (1.25, 1.25, 1.25)),
    "Torso": ((0, 0, 0), (2, 1, 2), (2, 1.05, 2)),
    "RightArm": ((1.5, 0, 0), (1, 1, 2), (0.9, 0.9, 2)),
    "LeftArm": ((-1.5, 0, 0), (1, 1, 2), (0.9, 0.9, 2)),
    "RightLeg": ((0.5, 0, -2), (1, 1, 2), (0.95, 0.95, 2)),
    "LeftLeg": ((-0.5, 0, -2), (1, 1, 2), (0.95, 0.95, 2)),
}
# the ninja builders fill R15 regions; these are the R6 parts they belong to
REGION_PART = {
    "Head": "Head", "UpperTorso": "Torso", "LowerTorso": "Torso",
    "RightUpperArm": "RightArm", "RightLowerArm": "RightArm", "RightHand": "RightArm",
    "RightUpperLeg": "RightLeg", "RightLowerLeg": "RightLeg", "RightFoot": "RightLeg",
}


# ---------------------------------------------------------------- materials
class Look(N.Look):
    def __init__(self, name, pal):
        super().__init__(name, pal["cloth"], pal["trim"], pal["dark"], pal.get("boot", pal["dark"]), noise=0.09, streaks=pal.get("streaks", 0.1))
        self.pal = pal
        self.skin = H.paint(name + "DSkin", pal["skin"], noise=0.07, scale=18, roughness=0.5)
        self.horn = H.paint(name + "Horn", pal.get("horn", (40, 34, 36)), noise=0.12, scale=40, streaks=0.2, roughness=0.35)
        self.bone = H.paint(name + "Bone", (238, 228, 205), noise=0.05, roughness=0.35)
        self.mouth = H.paint(name + "Mouth", (40, 8, 10), roughness=0.5)
        self.plate = H.paint(name + "Plate", pal.get("plate", pal["cloth"]), noise=0.05, scale=12, roughness=0.3, roblox="Metal")
        self.gold = H.paint(name + "Gold", pal.get("gold", (220, 170, 64)), noise=0.05, roughness=0.3, roblox="Metal")
        self.hair = H.paint(name + "Hair", pal.get("hair", (30, 24, 26)), noise=0.15, scale=50, streaks=0.3, roughness=0.7)
        self.iron = H.paint(name + "Iron", (70, 68, 74), noise=0.08, roughness=0.35, roblox="Metal")
        self.glowm = H.paint(name + "Glow", (255, 70, 40), roughness=0.2, emission=2.0, roblox="Neon")


# ---------------------------------------------------------------- shapes
def taper_tube(name, pts, radii, mat, sides=10):
    """Solid tapering along 3D points (horns, claws, tails, spikes); ends in a point."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    verts, rings = [], []
    prev = None
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        ref = prev if prev is not None else (Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0)))
        a = (ref - t * ref.dot(t)).normalized()
        b = t.cross(a)
        prev = a
        r = radii[i]
        ring = []
        for k in range(sides):
            ang = math.tau * k / sides
            ring.append(len(verts))
            verts.append(p + (a * math.cos(ang) + b * math.sin(ang)) * r)
        rings.append(ring)
    faces = []
    for i in range(n - 1):
        r0, r1 = rings[i], rings[i + 1]
        for k in range(sides):
            faces.append((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]))
    faces.append(tuple(reversed(rings[0])))
    tip = len(verts)
    verts.append(pts[-1] + (pts[-1] - pts[-2]).normalized() * radii[-1] * 1.5)
    for k in range(sides):
        faces.append((rings[-1][k], rings[-1][(k + 1) % sides], tip))
    o = C.mesh_object(name, verts, faces, mat, smooth=True)
    C.recalc_normals(o)
    return o


def horn(name, base, direction, length, radius, mat, bend=(0, 0, 0), twist=0.0, steps=12, sides=12, ridges=0.0):
    """Curved tapering horn: a quadratic curve from `base` along `direction`, bent by
    `bend` (studs at the tip), optionally spiralling (`twist`, turns) with ridges."""
    d = Vector(direction).normalized()
    bnd = Vector(bend)
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side.normalize()
    up = side.cross(d).normalized()
    pts, radii = [], []
    for i in range(steps + 1):
        t = i / steps
        p = Vector(base) + d * length * t + bnd * t * t
        if twist:
            a = math.tau * twist * t
            p += (side * math.cos(a) + up * math.sin(a)) * radius * 0.6 * t
        pts.append(p)
        r = radius * (1 - t) ** 0.85 + 0.008
        if ridges:
            r *= 1 + ridges * math.sin(t * 40) * (1 - t)
        radii.append(r)
    return taper_tube(name, pts, radii, mat, sides)


def fang(name, p, n, length, width, mat, down=(0, 0, -1)):
    """Small pointed tooth sitting on a surface point p (normal n), pointing `down`."""
    n = Vector(n).normalized()
    dn = Vector(down).normalized()
    side = n.cross(dn)
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side.normalize()
    base = Vector(p)
    verts = [base - side * width / 2, base + side * width / 2, base + side * width / 2 + n * width * 0.45, base - side * width / 2 + n * width * 0.45,
             base + dn * length + n * width * 0.25]
    faces = [(0, 1, 2, 3), (0, 4, 1), (1, 4, 2), (2, 4, 3), (3, 4, 0)]
    o = H.flat(name, verts, faces, mat)
    C.recalc_normals(o)
    return o


def jagged_tail(name, top, width, length, mat, points=3, thick=0.03, tilt=0.0, seed=0):
    """A torn cloth strip hanging from `top` (x, y, z), its bottom edge ripped into points."""
    x0, y0, z0 = top
    outline = [(x0 - width / 2, z0), (x0 + width / 2, z0)]
    rnd = __import__("random").Random(seed)
    for k in range(points * 2 + 1):
        u = 1 - k / (points * 2)
        depth = length * (1.0 if k % 2 == 0 else 0.72) * rnd.uniform(0.85, 1.05)
        outline.append((x0 - width / 2 + width * u, z0 - depth))
    o = C.extrude_outline(name, outline, thick, mat, axis="Y")
    o.location = (0, y0, 0)
    if tilt:
        o.rotation_euler = (tilt, 0, 0)
    C.apply_transforms([o])
    return o


def claws(L, region, x, z, forward=0.32, count=3, length=0.24, radius=0.045, spread=0.14, back=False):
    """Curved claws from the bottom-front of a hand or foot."""
    for i in range(count):
        dx = (i - (count - 1) / 2) * spread
        base = (x + dx, forward, z)
        L.add(region, horn(L.tier + "Claw%s%d%d" % (region, i, back), base, (0, 0.55, -1), length, radius, L.bone, bend=(0, 0.12, 0.04), steps=6, sides=8))


def spikes(L, region, pts, mat, length=0.3, radius=0.07):
    for i, (base, d) in enumerate(pts):
        L.add(region, horn(L.tier + "Spike%s%d" % (region, i), base, d, length, radius, mat, steps=4, sides=8))


def tail(L, tip_color_mat=None):
    """Long devil tail from the lower back, curling to one side, with a spade tip."""
    pts, radii = [], []
    for i in range(16):
        t = i / 15
        pts.append((0.35 * math.sin(t * 2.2) + 0.1, -0.52 - t * 1.1, -0.75 - 1.1 * math.sin(t * 1.4) + 0.9 * t * t))
        radii.append(0.1 * (1 - t) + 0.035)
    L.add("LowerTorso", taper_tube(L.tier + "Tail", pts[:-1], radii[:-1], L.skin, sides=10))
    tip = Vector(pts[-1])
    spade = [(-0.16, 0.0), (0.0, 0.3), (0.16, 0.0), (0.0, -0.08)]
    o = C.extrude_outline(L.tier + "Spade", [(tip.x + a, tip.z + b) for a, b in spade], 0.05, tip_color_mat or L.horn, axis="Y")
    o.location = (0, tip.y, 0)
    C.apply_transforms([o])
    L.add("LowerTorso", o)


# ---------------------------------------------------------------- heads
def face_mouth(L, target, z=1.27, width=0.3, fangs=6, big=True, region="Head"):
    """A dark grinning mouth with a row of fangs on the front of `target`."""
    path = N.path_on(target, [(-width, z + 0.03), (-width * 0.5, z - 0.01), (0, z - 0.02), (width * 0.5, z - 0.01), (width, z + 0.03)], 0.03)
    L.add(region, N.strip(L.tier + "Mouth", path, 0.1, 0.012, L.mouth, lift=0.004, bevel=0))
    for i in range(fangs):
        u = -width * 0.85 + i * (width * 1.7) / (fangs - 1)
        p, n = N.front(target, u, z + 0.03 - 0.04 * (1 - (u / width) ** 2))
        if p:
            L.add(region, fang(L.tier + "Fang%d" % i, p + n * 0.012, n, 0.07, 0.05, L.bone))
            p2, n2 = N.front(target, u + width * 0.85 / (fangs - 1), z - 0.07)
            if p2:
                L.add(region, fang(L.tier + "FangLo%d" % i, p2 + n2 * 0.012, n2, 0.05, 0.045, L.bone, down=(0, 0, 1)))
    if big:
        for side in (-1, 1):
            p, n = N.front(target, side * width * 1.05, z + 0.04)
            if p:
                L.add(region, fang(L.tier + "BigFang%d" % side, p + n * 0.012, n, 0.16, 0.075, L.bone))


def hood_head(L, st):
    N.head(L, {"eyes": "demon", "glow": L.glowm, "seam": st.get("seam", True), "brow": L.ink})
    mask = next(o for o in L.parts["Head"] if o.name == L.tier + "Mask")
    if st.get("grin", True):
        face_mouth(L, mask, z=1.26, width=0.3)
    kind = st.get("horns", "swept")
    if kind == "swept":
        for s in (-1, 1):
            L.add("Head", horn(L.tier + "Horn%d" % s, (s * 0.42, 0.22, 2.2), (s * 0.35, -0.25, 1), 0.55, 0.13, L.horn, bend=(s * 0.1, -0.45, -0.05), ridges=0.08))
    elif kind == "long":
        for s in (-1, 1):
            L.add("Head", horn(L.tier + "Horn%d" % s, (s * 0.4, 0.1, 2.22), (s * 0.3, -0.7, 0.6), 0.95, 0.12, L.horn, bend=(s * 0.1, -0.2, -0.25)))
    elif kind == "antenna":
        for s in (-1, 1):
            L.add("Head", horn(L.tier + "Horn%d" % s, (s * 0.25, 0.45, 2.15), (s * 0.35, 0.3, 1), 1.1, 0.05, L.horn, bend=(s * 0.35, 0.5, -0.4), steps=16, sides=8))
    elif kind == "single":
        L.add("Head", horn(L.tier + "Horn", (0, 0.35, 2.25), (0, 0.35, 1), 0.6, 0.14, L.horn, bend=(0, -0.3, 0), ridges=0.1))
    if st.get("nose"):  # tengu
        p, n = N.front(mask, 0, 1.52)
        L.add("Head", horn(L.tier + "Nose", p - n * 0.04, (0, 1, 0.15), 0.62, 0.11, L.skin, bend=(0, 0, 0.12), steps=8))


def arc_band(name, z0, z1, r0, r1, thick, mat, a0=math.radians(140), a1=math.radians(400), steps=40, power=2.4):
    """Curved plate hanging around the back of the head (from angle a0 to a1; +Y,
    the face, is at 90 degrees): top edge at z0 radius r0, bottom at z1 radius r1."""
    def at(a, r, z):
        c, s = math.cos(a), math.sin(a)
        return (r * math.copysign(abs(c) ** (2 / power), c), r * math.copysign(abs(s) ** (2 / power), s), z)
    verts, rings = [], []
    for k in range(steps + 1):
        a = a0 + (a1 - a0) * k / steps
        ring = []
        for r, z in ((r0, z0), (r1, z1), (r1 + thick, z1), (r0 + thick, z0)):
            ring.append(len(verts))
            verts.append(at(a, r, z))
        rings.append(ring)
    faces = []
    for k in range(steps):
        a, b = rings[k], rings[k + 1]
        for j in range(4):
            faces.append((a[j], a[(j + 1) % 4], b[(j + 1) % 4], b[j]))
    faces.append(tuple(rings[0]))
    faces.append(tuple(reversed(rings[-1])))
    o = C.mesh_object(name, verts, faces, mat)
    C.recalc_normals(o)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def kabuto_head(L, st):
    """Samurai demon: horned helmet, glowing eyes in a dark face, fanged menpo."""
    face = L.add("Head", N.rbox(L.tier + "Face", (0.6, 0.6, 0.62), (0, 0, 1.62), L.skin, power=3.2, segs=48, rings=32))
    for side in (-1, 1):
        s = side
        brow = [(s * 0.52, 1.92), (s * 0.45, 1.98), (s * 0.25, 1.9), (s * 0.05, 1.8), (s * 0.04, 1.73), (s * 0.13, 1.75), (s * 0.3, 1.83), (s * 0.48, 1.87)]
        L.add("Head", N.flat_shape(L.tier + "Brow%d" % side, brow, 0.6, L.ink, face, thick=0.03))
        slit = [(s * 0.12, 1.74), (s * 0.42, 1.83), (s * 0.4, 1.71), (s * 0.18, 1.665)]
        L.glow["Head"].append(N.flat_shape(L.tier + "Eye%d" % side, slit, 0.6, L.glowm, face, thick=0.03))
    # helmet bowl with ribs, a turned-up brim and a flared neck guard (shikoro)
    bowl = L.add("Head", S.lofted(L.tier + "Bowl", [(1.9, 0.72, 0.72), (2.05, 0.76, 0.76), (2.2, 0.72, 0.72), (2.33, 0.6, 0.6), (2.42, 0.4, 0.4), (2.46, 0.15, 0.15)], L.plate, power=2.2, n=48))
    for k in range(8):
        a = math.tau * k / 8
        pts = []
        for i in range(8):
            z = 1.92 + i * 0.075
            p, n = N.hit(bowl, (math.cos(a) * 3, math.sin(a) * 3, z), (-math.cos(a), -math.sin(a), 0))
            if p:
                pts.append(p + n * 0.01)
        if len(pts) > 2:
            L.add("Head", N.tube(L.tier + "Rib%d" % k, pts, 0.022, L.gold, sides=6))
    L.add("Head", S.lofted(L.tier + "Brim", [(1.9, 0.8, 0.8, 0, 0.06), (1.93, 0.86, 0.9, 0, 0.1)], L.plate, power=2.4, n=48))
    # shikoro: flared lames around the back and sides only, open at the face
    for i, (z, r) in enumerate(((1.86, 0.8), (1.7, 0.85), (1.54, 0.9))):
        L.add("Head", arc_band(L.tier + "Shikoro%d" % i, z, z - 0.17, r, r + 0.07, 0.05, L.plate))
        L.add("Head", arc_band(L.tier + "ShLace%d" % i, z - 0.14, z - 0.18, r + 0.058, r + 0.075, 0.062, L.trim))
    # menpo: metal lower face with a snarling fanged mouth
    menpo = L.add("Head", S.lofted(L.tier + "Menpo", [(1.02, 0.52, 0.5, 0, 0.08), (1.18, 0.64, 0.64, 0, 0.06), (1.36, 0.66, 0.68, 0, 0.05), (1.52, 0.62, 0.64, 0, 0.03)], L.plate, power=2.3, n=48))
    for side in (-1, 1):
        L.add("Head", N.strip(L.tier + "Cheek%d" % side, N.path_on(menpo, [(side * 0.2, 1.47), (side * 0.52, 1.3), (side * 0.42, 1.12)], 0.03), 0.05, 0.03, L.gold, lift=0.004, bevel=0.3))
    face_mouth(L, menpo, z=1.27, width=0.3, fangs=6)
    kind = st.get("horns", "crescent")
    if kind == "crescent":
        for s in (-1, 1):
            L.add("Head", horn(L.tier + "Horn%d" % s, (s * 0.3, 0.55, 2.08), (s * 0.9, 0.25, 0.7), 0.7, 0.1, L.gold, bend=(s * -0.05, 0.1, 0.55), steps=14))
    else:
        for s in (-1, 1):
            L.add("Head", horn(L.tier + "Horn%d" % s, (s * 0.45, 0.2, 2.2), (s * 0.55, -0.1, 1), 0.75, 0.14, L.horn, bend=(s * 0.25, -0.4, 0.1), ridges=0.08))
    L.add("Head", N.rbox(L.tier + "Crest", (0.12, 0.05, 0.12), (0, 0.72, 2.12), L.gold, power=3))
    L.glow["Head"].append(N.rbox(L.tier + "CrestGem", (0.07, 0.04, 0.07), (0, 0.76, 2.12), L.glowm, power=1.5, segs=8, rings=6))


def oni_head(L, st):
    """Bald oni: heavy brow, glowing eyes, tusked grin, wild mane, big horns."""
    head = L.add("Head", N.rbox(L.tier + "Skull", (0.72, 0.7, 0.74), (0, 0.0, 1.62), L.skin, power=3.2, segs=56, rings=40))
    L.add("Head", N.rbox(L.tier + "BrowRidge", (0.62, 0.16, 0.1), (0, 0.6, 1.9), L.skin, power=3))
    L.add("Head", N.rbox(L.tier + "Nose", (0.14, 0.12, 0.14), (0, 0.7, 1.55), L.skin, power=2.5))
    for side in (-1, 1):
        s = side
        brow = [(s * 0.56, 1.98), (s * 0.48, 2.03), (s * 0.26, 1.95), (s * 0.05, 1.84), (s * 0.04, 1.77), (s * 0.13, 1.79), (s * 0.3, 1.87), (s * 0.5, 1.93)]
        L.add("Head", N.flat_shape(L.tier + "Brow%d" % side, brow, 0.72, L.hair, head, thick=0.05))
        socket = [(s * 0.08, 1.8), (s * 0.46, 1.9), (s * 0.44, 1.7), (s * 0.16, 1.66)]
        L.add("Head", N.flat_shape(L.tier + "Socket%d" % side, socket, 0.72, L.ink, head, thick=0.02))
        slit = [(s * 0.12, 1.785), (s * 0.42, 1.865), (s * 0.4, 1.73), (s * 0.18, 1.69)]
        L.glow["Head"].append(N.flat_shape(L.tier + "Eye%d" % side, slit, 0.72, L.glowm, head, thick=0.035))
    face_mouth(L, head, z=1.3, width=0.36, fangs=7, big=False)
    for side in (-1, 1):
        p, n = N.front(head, side * 0.36, 1.24)
        if p:
            L.add("Head", horn(L.tier + "Tusk%d" % side, p - n * 0.02, (side * 0.15, 0.4, 1), 0.3, 0.07, L.bone, bend=(side * 0.05, 0.05, 0), steps=6, sides=8))
    # mane: tufts over the back and sides of the head
    rnd = __import__("random").Random(len(L.tier))
    for i in range(22):
        a = math.pi * (0.1 + 0.8 * i / 21) + math.pi
        z = 1.95 + rnd.uniform(-0.25, 0.3)
        base = (math.cos(a) * 0.6, math.sin(a) * 0.55, z)
        d = (math.cos(a) * 0.6, math.sin(a) * 0.8, rnd.uniform(-0.6, 0.2))
        L.add("Head", horn(L.tier + "Mane%d" % i, base, d, rnd.uniform(0.35, 0.55), 0.13, L.hair, bend=(0, 0, -0.2), steps=5, sides=7))
    for s in (-1, 1):
        L.add("Head", horn(L.tier + "Horn%d" % s, (s * 0.42, 0.2, 2.22), (s * 0.75, 0.1, 0.8), 0.95, 0.17, L.horn, bend=(s * -0.2, 0.15, 0.55), ridges=0.1, steps=16))


def imp_head(L, st):
    head = L.add("Head", N.rbox(L.tier + "Skull", (0.7, 0.68, 0.72), (0, 0.0, 1.62), L.skin, power=3.0, segs=56, rings=40))
    for side in (-1, 1):
        s = side
        brow = [(s * 0.54, 1.96), (s * 0.46, 2.02), (s * 0.25, 1.94), (s * 0.05, 1.83), (s * 0.04, 1.76), (s * 0.13, 1.78), (s * 0.3, 1.86), (s * 0.49, 1.91)]
        L.add("Head", N.flat_shape(L.tier + "Brow%d" % side, brow, 0.7, L.ink, head, thick=0.04))
        eye = [(s * 0.1, 1.79), (s * 0.44, 1.9), (s * 0.44, 1.7), (s * 0.17, 1.65)]
        L.add("Head", N.flat_shape(L.tier + "Socket%d" % side, eye, 0.7, L.ink, head, thick=0.02))
        slit = [(s * 0.14, 1.775), (s * 0.4, 1.86), (s * 0.4, 1.72), (s * 0.19, 1.68)]
        L.glow["Head"].append(N.flat_shape(L.tier + "Eye%d" % side, slit, 0.7, L.glowm, head, thick=0.035))
        # pointed ears
        L.add("Head", horn(L.tier + "Ear%d" % s, (s * 0.66, -0.05, 1.7), (s * 1, -0.2, 0.35), 0.4, 0.13, L.skin, bend=(0, -0.05, 0.08), steps=6))
    face_mouth(L, head, z=1.32, width=0.34, fangs=7)
    for s in (-1, 1):
        L.add("Head", horn(L.tier + "Horn%d" % s, (s * 0.38, 0.25, 2.2), (s * 0.5, 0.1, 1), 0.85, 0.15, L.horn, bend=(s * 0.25, -0.35, 0.05), ridges=0.1, twist=0.3, steps=16))


# ---------------------------------------------------------------- bodies
def move_to_glow(L, region, key):
    keep = []
    for o in L.parts[region]:
        (L.glow[region] if key in o.name else keep).append(o)
    L.parts[region] = keep


def hood_body(L, st):
    jacket = N.torso(L, {"vneck": L.skin, "collar": L.dark})
    if st.get("sigil", True):
        # three glowing claw scars torn across the free side of the chest
        for k in range(3):
            pts = N.path_on(jacket, [(-0.28 - k * 0.14, 0.66), (-0.46 - k * 0.14, 0.08)], 0.03)
            L.glow["UpperTorso"].append(N.strip(L.tier + "Scar%d" % k, pts, 0.055, 0.02, L.glowm, lift=0.004, bevel=0, taper=lambda t: 0.3 + 0.7 * math.sin(t * math.pi)))
    N.hips(L, {"belt": "knot"})
    for i, (x, y, w, ln, tilt) in enumerate(((-0.55, 0.57, 0.28, 0.55, 0.12), (0.35, 0.58, 0.22, 0.45, 0.1), (0.1, -0.58, 0.34, 0.6, -0.1), (-0.6, -0.57, 0.24, 0.5, -0.1))):
        L.add("LowerTorso", jagged_tail(L.tier + "Rag%d" % i, (x, y, -0.66), w, ln, L.dark if i % 2 else L.trim, points=2 + i % 2, tilt=tilt, seed=i))
    N.arm(L, {"cuff": True})
    L.parts["RightHand"] = []
    L.add("RightHand", N.rbox(L.tier + "Hand", (0.39, 0.44, 0.17), (1.43, 0, -0.88), L.skin, power=14))
    claws(L, "RightHand", 1.43, -0.98, forward=0.28)
    if st.get("pad", True):
        pad = N.rbox(L.tier + "Pad", (0.5, 0.56, 0.15), (0, 0, 0), L.iron, power=8)
        pad.rotation_euler = (0, -0.25, 0)
        pad.location = (1.5, 0, 0.98)
        C.apply_transforms([pad])
        L.add("RightUpperArm", pad)
        spikes(L, "RightUpperArm", [((1.4 + i * 0.16, (-0.2, 0.0, 0.2)[i], 1.1 - i * 0.04), (0.3 + i * 0.2, 0, 1)) for i in range(3)], L.bone, 0.32, 0.08)
    N.leg(L, {"wraps": True, "x": L.dark, "sash": L.trim})


def samurai_body(L, st):
    N.torso(L, {"vneck": L.skin, "collar": L.dark})
    # do: lacquered chest plate over the jacket, with laced lames below
    do = L.add("UpperTorso", N.rbox(L.tier + "Do", (1.08, 0.6, 0.42), (0, 0, 0.5), L.plate, power=8, segs=48, rings=24))
    for i, z in enumerate((0.02, -0.16, -0.34)):
        L.add("UpperTorso", N.rbox(L.tier + "Lame%d" % i, (1.07 - i * 0.005, 0.59, 0.085), (0, 0, z), L.plate, power=12, segs=32, rings=8))
        L.add("UpperTorso", N.rbox(L.tier + "Lace%d" % i, (1.075, 0.595, 0.02), (0, 0, z - 0.08), L.trim, power=12, segs=32, rings=4))
    for side in (-1, 1):
        L.add("UpperTorso", N.strip(L.tier + "DoTrim%d" % side, N.path_on(do, [(side * 0.9, 0.86), (side * 0.3, 0.9), (0, 0.72)], 0.04), 0.06, 0.03, L.gold, lift=0.004, bevel=0.3))
    if st.get("sigil", True):
        pts = N.path_on(do, [(0, 0.78), (-0.16, 0.56), (0, 0.34), (0.16, 0.56), (0, 0.78)], 0.03)
        L.glow["UpperTorso"].append(N.strip(L.tier + "Sigil", pts, 0.05, 0.015, L.glowm, lift=0.004, bevel=0))
    N.hips(L, {"belt": "knot"})
    # kusazuri: hanging hip plates front, back and sides
    for i, (x, y, rot) in enumerate(((-0.5, 0.62, 0.18), (0.5, 0.62, 0.18), (-0.5, -0.62, -0.18), (0.5, -0.62, -0.18))):
        for k in range(3):
            p = N.rbox(L.tier + "Kusa%d%d" % (i, k), (0.42, 0.07, 0.09), (0, 0, 0), L.plate if k < 2 else L.trim, power=10, segs=16, rings=8)
            p.rotation_euler = (rot, 0, 0)
            p.location = (x, y + math.copysign(0.03 * k, y), -0.82 - k * 0.17)
            C.apply_transforms([p])
            L.add("LowerTorso", p)
    for side in (-1, 1):
        for k in range(3):
            p = N.rbox(L.tier + "KusaS%d%d" % (side, k), (0.07, 0.45, 0.09), (side * (1.08 + 0.03 * k), 0, -0.82 - k * 0.17), L.plate if k < 2 else L.trim, power=10, segs=16, rings=8)
            L.add("LowerTorso", p)
    N.arm(L, {"cuff": False})
    # sode: layered shoulder plates with lacing
    for k in range(3):
        pad = N.rbox(L.tier + "Sode%d" % k, (0.5, 0.57, 0.1), (0, 0, 0), L.plate if k < 2 else L.trim, power=10)
        pad.rotation_euler = (0, -0.28, 0)
        pad.location = (1.53 + k * 0.05, 0, 0.98 - k * 0.19)
        C.apply_transforms([pad])
        L.add("RightUpperArm", pad)
    spikes(L, "RightUpperArm", [((1.5, -0.25 + 0.25 * i, 1.08), (0.4, 0, 1)) for i in range(3)], L.horn, 0.28, 0.07)
    L.add("RightLowerArm", N.rbox(L.tier + "Kote", (0.44, 0.5, 0.3), (1.43, 0, -0.44), L.plate, power=10))
    L.add("RightLowerArm", N.rbox(L.tier + "KoteBand", (0.45, 0.51, 0.04), (1.43, 0, -0.2), L.gold, power=10))
    L.parts["RightHand"] = []
    L.add("RightHand", N.rbox(L.tier + "Hand", (0.39, 0.44, 0.17), (1.43, 0, -0.88), L.dark, power=14))
    claws(L, "RightHand", 1.43, -0.98, forward=0.28)
    N.leg(L, {})
    sune = L.add("RightLowerLeg", N.rbox(L.tier + "Suneate", (0.48, 0.52, 0.34), (0.49, 0.02, -2.2), L.plate, power=10))
    for k in (-1, 0, 1):
        pts = N.path_on(sune, [(-0.49 + k * 0.15, -1.93), (-0.49 + k * 0.15, -2.47)], 0.04)
        L.add("RightLowerLeg", N.strip(L.tier + "SuneRib%d" % k, pts, 0.035, 0.02, L.gold, lift=0.003, bevel=0.3))
    L.add("RightUpperLeg", N.rbox(L.tier + "Haidate", (0.48, 0.53, 0.25), (0.49, 0.02, -1.35), L.plate, power=10))


def muscle_arm(L, x, skin):
    L.add("RightUpperArm", N.rbox(L.tier + "Delt", (0.47, 0.5, 0.3), (x + 0.02, 0, 0.82), skin, power=3.2))
    L.add("RightUpperArm", N.rbox(L.tier + "Bicep", (0.43, 0.47, 0.42), (x, 0.02, 0.4), skin, power=3.6))
    L.add("RightLowerArm", N.rbox(L.tier + "Forearm", (0.42, 0.46, 0.44), (x, 0, -0.3), skin, power=4))


def oni_body(L, st):
    chest = L.add("UpperTorso", N.rbox(L.tier + "Chest", (1.0, 0.52, 0.86), (0, 0, 0.16), L.skin, power=5, segs=48, rings=32))
    for side in (-1, 1):
        L.add("UpperTorso", N.rbox(L.tier + "Pec%d" % side, (0.44, 0.14, 0.26), (side * 0.45, 0.44, 0.5), L.skin, power=2.6))
        for k in range(3):
            L.add("UpperTorso", N.rbox(L.tier + "Ab%d%d" % (side, k), (0.17, 0.08, 0.13), (side * 0.19, 0.5, 0.1 - k * 0.27), L.skin, power=2.6))
    if st.get("sigil", True):
        for k in range(3):
            pts = N.path_on(chest, [(0.3 + k * 0.12, 0.72), (0.52 + k * 0.12, 0.02)], 0.03)
            L.glow["UpperTorso"].append(N.strip(L.tier + "Scar%d" % k, pts, 0.05, 0.02, L.glowm, lift=0.1, bevel=0, taper=lambda t: 0.3 + 0.7 * math.sin(t * math.pi)))
    # rope belt and tiger-skin loincloth
    skirt = L.add("LowerTorso", N.rbox(L.tier + "Loin", (1.04, 0.56, 0.3), (0, 0, -0.78), L.cloth, power=12, segs=48, rings=16))
    rnd = __import__("random").Random(3)
    for k in range(12):
        a = math.tau * k / 12 + rnd.uniform(-0.1, 0.1)
        pts = []
        for i in range(7):
            z = -0.58 - i * 0.07
            p, n = N.hit(skirt, (math.cos(a) * 3, math.sin(a) * 3, z + math.sin(i + k) * 0.02), (-math.cos(a), -math.sin(a), 0))
            if p:
                pts.append((p, n))
        if len(pts) > 2:
            L.add("LowerTorso", N.strip(L.tier + "Stripe%d" % k, pts, 0.08, 0.008, L.dark, lift=0.002, bevel=0, taper=lambda t: 1 - t * 0.8))
    ring = [(math.cos(a) * 1.07, math.sin(a) * 0.6, -0.52 + 0.02 * math.sin(a * 3)) for a in [math.tau * k / 40 for k in range(40)]]
    L.add("LowerTorso", N.tube(L.tier + "Rope", ring, 0.07, L.trim, closed=True, sides=10))
    L.add("LowerTorso", N.rbox(L.tier + "RopeKnot", (0.14, 0.1, 0.12), (0.3, 0.63, -0.52), L.trim, power=3))
    L.add("LowerTorso", jagged_tail(L.tier + "Flap", (0, 0.6, -0.62), 0.6, 0.62, L.cloth, points=3, thick=0.04, tilt=0.08))
    x = 1.43
    muscle_arm(L, x, L.skin)
    L.add("RightLowerArm", N.rbox(L.tier + "Bracer", (0.46, 0.5, 0.26), (x, 0, -0.45), L.iron, power=8))
    spikes(L, "RightLowerArm", [((x + 0.45, 0, -0.45 + dz), (1, 0, 0.1)) for dz in (-0.12, 0.12)] + [((x, 0.5, -0.45), (0, 1, 0))], L.bone, 0.22, 0.07)
    L.add("RightHand", N.rbox(L.tier + "Hand", (0.41, 0.46, 0.18), (x, 0, -0.88), L.skin, power=6))
    claws(L, "RightHand", x, -0.98, forward=0.3, length=0.3, radius=0.055)
    lx = 0.49
    L.add("RightUpperLeg", N.rbox(L.tier + "Thigh", (0.47, 0.5, 0.5), (lx, 0, -1.47), L.skin, power=5))
    shin = L.add("RightLowerLeg", N.rbox(L.tier + "Shin", (0.45, 0.48, 0.36), (lx, 0, -2.2), L.skin, power=5))
    L.add("RightLowerLeg", N.rbox(L.tier + "Fur", (0.5, 0.53, 0.14), (lx, 0, -2.05), L.hair, power=4))
    for i in range(10):
        a = math.tau * i / 10
        L.add("RightLowerLeg", horn(L.tier + "FurTuft%d" % i, (lx + math.cos(a) * 0.45, math.sin(a) * 0.48, -2.0), (math.cos(a), math.sin(a), -0.8), 0.22, 0.09, L.hair, steps=4, sides=6))
    del shin
    L.add("RightFoot", N.rbox(L.tier + "Foot", (0.47, 0.58, 0.24), (lx, 0.06, -2.74), L.skin, power=5))
    claws(L, "RightFoot", lx, -2.84, forward=0.55, length=0.2, radius=0.05, spread=0.15)
    L.add("RightFoot", N.rbox(L.tier + "Anklet", (0.5, 0.54, 0.06), (lx, 0.03, -2.5), L.iron, power=10))
    if st.get("tail"):
        tail(L)


def imp_body(L, st):
    N.torso(L, {"vneck": L.skin, "collar": None})
    L.parts["UpperTorso"] = [o for o in L.parts["UpperTorso"] if "Lapel" not in o.name]
    L.add("UpperTorso", N.strip(L.tier + "Strap", N.path_on(L.parts["UpperTorso"][0], [(0.7, 0.95), (-0.6, -0.5)], 0.05), 0.16, 0.04, L.trim, lift=0.004, bevel=0.4))
    oni_like = dict(st)
    oni_like["sigil"] = False
    skirt = L.add("LowerTorso", N.rbox(L.tier + "Loin", (1.04, 0.56, 0.28), (0, 0, -0.78), L.cloth, power=12, segs=48, rings=16))
    del skirt
    L.add("LowerTorso", N.rbox(L.tier + "Belt", (1.07, 0.585, 0.09), (0, 0, -0.56), L.trim, power=14, segs=48, rings=12))
    for i, x in enumerate((-0.5, 0.0, 0.5)):
        L.add("LowerTorso", jagged_tail(L.tier + "Rag%d" % i, (x, 0.58, -0.6), 0.36, 0.55, L.cloth if i != 1 else L.dark, points=2, tilt=0.1, seed=i + 7))
    x = 1.43
    muscle_arm(L, x, L.skin)
    L.add("RightLowerArm", N.rbox(L.tier + "Band", (0.44, 0.48, 0.07), (x, 0, -0.55), L.gold, power=10))
    L.add("RightHand", N.rbox(L.tier + "Hand", (0.4, 0.45, 0.17), (x, 0, -0.88), L.skin, power=6))
    claws(L, "RightHand", x, -0.98, forward=0.3)
    lx = 0.49
    L.add("RightUpperLeg", N.rbox(L.tier + "Thigh", (0.46, 0.5, 0.5), (lx, 0, -1.47), L.skin, power=5))
    L.add("RightLowerLeg", N.rbox(L.tier + "Shin", (0.44, 0.47, 0.36), (lx, 0, -2.2), L.skin, power=5))
    L.add("RightFoot", N.rbox(L.tier + "Hoof", (0.47, 0.55, 0.24), (lx, 0.04, -2.74), L.horn, power=5))
    L.add("RightFoot", C.box(L.tier + "HoofSplit", (0.04, 0.3, 0.3), (lx, 0.45, -2.74), L.ink))
    tail(L)


FAMILIES = {
    "hood": (hood_head, hood_body),
    "samurai": (kabuto_head, samurai_body),
    "oni": (oni_head, oni_body),
    "imp": (imp_head, imp_body),
}

# ---------------------------------------------------------------- variants
VARIANTS = {
    # hooded demon ninjas
    "shadow": ("hood", {"cloth": (44, 40, 48), "trim": (150, 26, 32), "dark": (24, 20, 26), "skin": (128, 34, 38), "horn": (30, 26, 28)}, {}),
    "bandit": ("hood", {"cloth": (112, 72, 42), "trim": (168, 64, 34), "dark": (60, 36, 22), "skin": (150, 52, 40), "horn": (226, 214, 188)}, {"horns": "single", "seam": False}),
    "bamboo": ("hood", {"cloth": (78, 110, 52), "trim": (210, 188, 96), "dark": (44, 62, 30), "skin": (160, 60, 44), "horn": (60, 48, 30)}, {"horns": "swept", "seam": False}),
    "mantis": ("hood", {"cloth": (92, 168, 64), "trim": (232, 216, 86), "dark": (46, 92, 34), "skin": (120, 190, 80), "horn": (60, 110, 40)}, {"horns": "antenna", "pad": False, "grin": True}),
    "shade": ("hood", {"cloth": (30, 22, 44), "trim": (112, 54, 190), "dark": (16, 12, 24), "skin": (70, 50, 96), "horn": (22, 18, 30)}, {"horns": "long"}),
    "tengu": ("hood", {"cloth": (226, 226, 236), "trim": (80, 150, 230), "dark": (60, 76, 120), "skin": (196, 40, 40), "horn": (40, 34, 40)}, {"horns": "swept", "nose": True, "seam": False, "grin": False}),
    # armoured demon samurai
    "samurai_red": ("samurai", {"cloth": (40, 32, 34), "trim": (40, 70, 160), "dark": (24, 20, 22), "skin": (110, 30, 34), "plate": (168, 32, 36), "gold": (224, 176, 70)}, {}),
    "samurai_black": ("samurai", {"cloth": (120, 22, 30), "trim": (170, 30, 38), "dark": (24, 20, 22), "skin": (60, 50, 56), "plate": (34, 32, 40), "gold": (232, 190, 80)}, {"horns": "oni", "horn": (28, 24, 28)}),
    "samurai_jade": ("samurai", {"cloth": (46, 56, 44), "trim": (190, 150, 70), "dark": (28, 34, 28), "skin": (120, 140, 120), "plate": (82, 118, 86), "gold": (200, 170, 90)}, {}),
    "samurai_ember": ("samurai", {"cloth": (54, 34, 30), "trim": (220, 90, 30), "dark": (30, 20, 18), "skin": (90, 36, 28), "plate": (64, 40, 36), "gold": (240, 150, 50)}, {"horns": "oni"}),
    "void": ("samurai", {"cloth": (36, 16, 60), "trim": (130, 60, 200), "dark": (16, 8, 26), "skin": (40, 24, 60), "plate": (28, 20, 40), "gold": (170, 110, 230)}, {"horns": "oni"}),
    # oni brutes
    "oni_red": ("oni", {"cloth": (232, 160, 40), "trim": (214, 196, 150), "dark": (30, 24, 20), "skin": (184, 40, 40), "horn": (238, 226, 200), "hair": (30, 22, 22)}, {"tail": False}),
    "oni_blue": ("oni", {"cloth": (232, 160, 40), "trim": (214, 196, 150), "dark": (30, 24, 20), "skin": (52, 96, 176), "horn": (238, 226, 200), "hair": (240, 240, 240)}, {"tail": False}),
    # imps
    "imp": ("imp", {"cloth": (60, 22, 18), "trim": (120, 80, 40), "dark": (30, 12, 10), "skin": (206, 56, 36), "horn": (40, 30, 30), "gold": (230, 170, 60)}, {}),
}


# ---------------------------------------------------------------- bake + export
MAX_TRIS = 19000  # Roblox rejects meshes over 20k triangles
MIN_TRIS = 2500  # smaller meshes are left alone
KEEP = 0.45  # share of triangles kept when decimating


def finish(L, name):
    atlas = [o for r in N.REGIONS if not r.startswith("Left") for o in L.parts[r]]
    weights = {o.name: 1.7 for o in L.parts["Head"]}
    bake.bake_atlas(atlas, os.path.join(TEX, name + ".png"), name, size=512, ao=0.45, ao_distance=0.15, ao_samples=96, weights=weights)
    N.mirror_limbs(L)
    by_part = {p: {"parts": [], "glow": []} for p in PARTS}
    for region in N.REGIONS:
        part = REGION_PART.get(region) or ("Left" + REGION_PART["Right" + region[4:]][5:])
        for kind in ("parts", "glow"):
            by_part[part][kind] += getattr(L, kind)[region]
    layout, shipped = [], []
    for part, (center, size, ref) in PARTS.items():
        for kind, suffix in (("parts", ""), ("glow", "__Glow")):
            objs = by_part[part][kind]
            if not objs:
                continue
            o = C.merge(objs, "%s_%s%s" % (name, part, suffix))
            if "Decal" in o.data.uv_layers:
                o.data.uv_layers.remove(o.data.uv_layers["Decal"])
            H.triangulate(o)
            n = len(o.data.polygons)
            target = min(MAX_TRIS, max(MIN_TRIS, int(n * KEEP)))
            if n > target:
                # the sculpt is dense where it doesn't need to be; many enemies share a
                # screen, so collapse it (UVs follow, the baked texture still fits)
                m = o.modifiers.new("Decimate", "DECIMATE")
                m.ratio = target / n
                C.apply_modifiers(o)
                H.triangulate(o)
            C.shade_auto(o, 50)
            s = o.copy()
            s.data = o.data.copy()
            bpy.context.scene.collection.objects.link(s)
            final = o.name
            o.name = final + "_layout"
            s.name = final
            s.data.name = final
            k = Vector(ref[i] / size[i] for i in range(3))
            s.data.transform(Matrix.Diagonal((k.x, k.y, k.z, 1)) @ Matrix.Translation(-Vector(center)))
            layout.append(o)
            shipped.append(s)
    return layout, shipped


def main():
    C.reset_scene()
    shipped = []
    for variant, (family, pal, st) in VARIANTS.items():
        if ONLY and variant not in ONLY:
            continue
        pal = dict(pal)
        if "horn" in st:
            pal["horn"] = st["horn"]
        L = Look(variant, pal)
        head_fn, body_fn = FAMILIES[family]
        head_fn(L, st)
        body_fn(L, st)
        layout, ship = finish(L, "HeroDemon_" + variant)
        shipped += ship
        H.studio_render(os.path.join(PREV, variant + ".png"), layout, view=(0, 1, 0), up=(0, 0, 1), size=(700, 1100), margin=1.1, samples=48)
        H.studio_render(os.path.join(PREV, variant + "_34.png"), layout, view=(-0.8, 1, 0.25), up=(0, 0, 1), size=(700, 1100), margin=1.1, ortho=False, samples=48)
        for o in layout:
            o.hide_render = True
            o.location.x += 50
    C.write_manifest(os.path.join(OUT, "HeroDemons.lua"), "hero_demons.py", shipped,
                     "each piece is centred on its R6 enemy part and sized for DEMON_REF (EnemyBuilder)")
    C.export_fbx(os.path.join(OUT, "NinjaSim_HeroDemons.fbx"), shipped, embed=True)
    for o in shipped:
        print("MESH", o.name, sum(len(p.vertices) - 2 for p in o.data.polygons), "tris")


if __name__ == "__main__":
    main()
