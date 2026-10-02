"""Hero ninja suits modelled after justin's reference sheets (brown, green, blue).

Each tier is one full blocky body built in an R6 layout (torso 2x2x1 centred on the
origin, character facing Blender +Y, its right side at +X), baked into ONE texture
(assets/textures/HeroNinja_<tier>.png, colour x AO), then cut into one mesh per R15
body part: HeroNinja_<tier>_<Part> (Head, UpperTorso, LowerTorso, Right/Left UpperArm,
LowerArm, Hand, UpperLeg, LowerLeg, Foot) plus HeroNinja_<tier>_<Part>__Glow neon bits.

Every piece is exported centred on its body region and stretched to the default R15
part size (SUIT_REF in OutfitBuilder.lua), so the game can weld it to R15 parts or to
the R6 limb regions exactly like the NSuit pieces.

Run: python3 tools/blender/hero_ninjas.py <out_dir> [tiers...]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import bake  # noqa: E402
import common as C  # noqa: E402
import hero as H  # noqa: E402
import sculpt as S  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/hero_ninjas"
ONLY = sys.argv[2:]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# HERO_TEX / HERO_PREV redirect textures and previews (scratch renders while iterating)
TEX = os.environ.get("HERO_TEX") or os.path.join(ROOT, "assets", "textures")
PREV = os.environ.get("HERO_PREV") or os.path.join(ROOT, "assets", "previews", "hero")
FAST = os.environ.get("HERO_FAST") == "1"  # look-dev only: no bake, quick renders
for d in (OUT, TEX, PREV):
    os.makedirs(d, exist_ok=True)

# region -> (centre, size in the R6 layout, default R15 part size) ; sizes are (x, depth, height)
REGIONS = {
    "Head": ((0, 0, 1.6), (1.2, 1.2, 1.2), (1.2, 1.2, 1.2)),
    "UpperTorso": ((0, 0, 0.2), (2, 1, 1.6), (2, 1, 1.6)),
    "LowerTorso": ((0, 0, -0.8), (2, 1, 0.4), (2, 1, 0.4)),
    "RightUpperArm": ((1.5, 0, 0.55), (1, 1, 0.9), (1, 1, 1.169)),
    "RightLowerArm": ((1.5, 0, -0.325), (1, 1, 0.85), (1, 1, 1.052)),
    "RightHand": ((1.5, 0, -0.875), (1, 1, 0.25), (1, 1, 0.3)),
    "RightUpperLeg": ((0.5, 0, -1.475), (1, 1, 0.95), (1, 1, 1.217)),
    "RightLowerLeg": ((0.5, 0, -2.375), (1, 1, 0.85), (1, 1, 1.193)),
    "RightFoot": ((0.5, 0, -2.9), (1, 1, 0.2), (1, 1, 0.3)),
}
for _k in [k for k in REGIONS if k.startswith("Right")]:
    (cx, cy, cz), size, ref = REGIONS[_k]
    REGIONS["Left" + _k[5:]] = ((-cx, cy, cz), size, ref)

SKIN = (246, 196, 36)


# ---------------------------------------------------------------- geometry helpers
def rbox(name, half, center, mat, power=6.0, segs=32, rings=20):
    """Soft rounded block (superellipsoid): the toy-like body pieces."""
    return S.ellipsoid(name, half, center, mat, power=power, segs=segs, rings=rings)


def hit(target, origin, direction):
    bpy.context.view_layer.update()
    inv = target.matrix_world.inverted()
    ok, loc, nrm, _ = target.ray_cast(inv @ Vector(origin), (inv.to_3x3() @ Vector(direction)).normalized())
    if not ok:
        return None, None
    return target.matrix_world @ loc, (target.matrix_world.to_3x3() @ nrm).normalized()


def front(target, vx, z, back=False):
    """Surface point + normal on the front (+Y) of target at viewer-x vx (viewer's left
    is the character's right, so x = -vx)."""
    s = -1 if back else 1
    return hit(target, (-vx, 6 * s, z), (0, -s, 0))


def strip(name, samples, width, thick, mat, lift=0.004, bevel=0.35, taper=None):
    """Raised band hugging a surface. samples: [(point, normal)] along its centre line."""
    pts = [p for p, _ in samples]
    verts, rings = [], []
    n = len(samples)
    for i, (p, nrm) in enumerate(samples):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        a = nrm.cross(t).normalized()
        w = width * (taper(i / (n - 1)) if taper else 1.0)
        base = p + nrm * lift
        top = base + nrm * thick
        ring = [base - a * w / 2, base + a * w / 2, top + a * w / 2, top - a * w / 2]
        rings.append(list(range(len(verts), len(verts) + 4)))
        verts += ring
    o = H.flat(name, verts, C.loft(rings), mat)
    if bevel:
        m = o.modifiers.new("B", "BEVEL")
        m.width = thick * bevel
        m.segments = 2
        m.limit_method = "ANGLE"
        C.apply_modifiers(o)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def tube(name, pts, radius, mat, closed=False, sides=8):
    """Round cord through 3D points (hood rims, seams, ropes)."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    verts, rings = [], []
    prev_a = None
    for i, p in enumerate(pts):
        if closed:
            t = (pts[(i + 1) % n] - pts[(i - 1) % n]).normalized()
        else:
            t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        ref = prev_a if prev_a is not None else (Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0)))
        a = (ref - t * ref.dot(t)).normalized()
        b = t.cross(a)
        prev_a = a
        ring = []
        for k in range(sides):
            ang = math.tau * k / sides
            ring.append(len(verts))
            verts.append(p + (a * math.cos(ang) + b * math.sin(ang)) * radius)
        rings.append(ring)
    faces = []
    m = n if closed else n - 1
    for i in range(m):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for k in range(sides):
            faces.append((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]))
    if not closed:
        faces += [tuple(reversed(rings[0])), tuple(rings[-1])]
    o = C.mesh_object(name, verts, faces, mat, smooth=True)
    C.recalc_normals(o)
    return o


def cut(target, cutter, name=None):
    """Boolean difference; the new faces take the cutter's material (face pockets, V necks)."""
    for m in cutter.data.materials:
        if m.name not in [x.name for x in target.data.materials if x]:
            target.data.materials.append(m)
    mod = target.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    mod.material_mode = "TRANSFER"
    C.apply_modifiers(target)
    bpy.data.objects.remove(cutter)
    return target


def displace(o, fn):
    return S.displace(o, fn)


def ring_folds(z0, z1, count, depth, cx=None):
    """Horizontal soft folds between z0 and z1 (sleeves above the elbow / cuff)."""
    def fn(co, n):
        if not (z0 < co.z < z1) or abs(n.z) > 0.7:
            return 0.0
        t = (co.z - z0) / (z1 - z0)
        env = math.sin(t * math.pi)
        wob = 0.35 * math.sin(co.x * 7 + co.y * 5)
        return depth * env * math.sin(t * math.pi * count + wob)
    return fn


def flat_shape(name, outline_v, z_face, mat, target, thick=0.012):
    """A thin flat shape (eye, brow) given in viewer coords [(vx, z)], laid on the
    surface of target in front of it."""
    cx = sum(p[0] for p in outline_v) / len(outline_v)
    cz = sum(p[1] for p in outline_v) / len(outline_v)
    p, nrm = front(target, cx, cz)
    y = (p.y if p else z_face) + 0.004
    o = C.extrude_outline(name, [(-vx, z) for vx, z in outline_v], thick, mat, axis="Y")
    o.location = (0, y + thick / 2, 0)
    C.apply_transforms([o])
    return o


def gem_eye(name, cvx, cz, w, h, mat, target, side):
    """Faceted diamond eye (the green / blue refs): flat top, pointed bottom, raised facets."""
    p, _ = front(target, cvx, cz)
    y = p.y + 0.004
    top = [(-0.5, 0.25), (-0.25, 0.5), (0.25, 0.5), (0.5, 0.25)]
    tip = (0.0, -0.55)
    verts = [(cvx + u * w, cz + v * h) for u, v in top] + [(cvx + tip[0] * w, cz + tip[1] * h)]
    # front apex points (raised) for the crown and pavilion facets
    apex_c = (cvx, cz + 0.33 * h)
    apex_p = (cvx, cz - 0.05 * h)
    vs, fs = [], []
    ring = [(-vx, y, z) for vx, z in verts]
    vs += ring
    vs.append((-apex_c[0], y + 0.03, apex_c[1]))
    vs.append((-apex_p[0], y + 0.04, apex_p[1]))
    vs += [(-vx, y - 0.02, z) for vx, z in verts]
    ic, ip = 5, 6
    fs += [(0, 1, ic), (1, 2, ic), (2, 3, ic), (3, 0, ip), (0, ic, ip), (ic, 3, ip)]
    fs += [(3, 4, ip), (4, 0, ip)]
    b = 7
    for i in range(5):
        j = (i + 1) % 5
        fs.append((i, j, b + j, b + i))
    fs.append(tuple(b + i for i in range(5)))
    return H.flat(name, vs, fs, mat)


# ---------------------------------------------------------------- one ninja
class Look:
    def __init__(self, tier, cloth, trim, dark, boot, noise=0.08, streaks=0.12):
        self.tier = tier
        self.cloth = H.paint(tier + "Cloth", cloth, noise=noise, scale=22, streaks=streaks, roblox="Fabric")
        self.trim = H.paint(tier + "Trim", trim, noise=noise, scale=22, streaks=streaks * 0.7, roblox="Fabric")
        self.dark = H.paint(tier + "Dark", dark, noise=noise, scale=22, roblox="Fabric")
        self.boot = H.paint(tier + "Boot", boot, noise=noise * 0.8, scale=22, roblox="Fabric")
        self.skin = H.paint(tier + "Skin", SKIN, roughness=0.45)
        self.ink = H.paint(tier + "Ink", (22, 16, 12), roughness=0.4)
        self.metal = H.paint(tier + "Metal", (176, 178, 184), noise=0.05, roughness=0.3, roblox="Metal")
        self.metal_dark = H.paint(tier + "MetalDark", (64, 64, 70), roughness=0.4)
        self.parts = {k: [] for k in REGIONS}
        self.glow = {k: [] for k in REGIONS}

    def add(self, region, o):
        self.parts[region].append(o)
        return o


def head(L, style):
    hood = L.add("Head", rbox(L.tier + "Hood", (0.77, 0.75, 0.77), (0, -0.02, 1.73), L.cloth, power=2.8, segs=64, rings=40))
    # face window: a rounded pocket whose back wall is the yellow face
    win_w, win_h, win_z = 0.61, 0.3, 1.71
    rim_pts = []
    for k in range(48):
        a = math.tau * k / 48
        c, s = math.cos(a), math.sin(a)
        vx = math.copysign(abs(c) ** (2 / 6), c) * (win_w + 0.015)
        z = win_z + math.copysign(abs(s) ** (2 / 6), s) * (win_h + 0.015)
        p, _ = front(hood, vx, z)
        rim_pts.append(p + Vector((0, 0.005, 0)))
    cutter = rbox(L.tier + "Win", (win_w, 0.5, win_h), (0, 0.6 + 0.5, win_z), L.skin, power=6)
    cut(hood, cutter)
    L.add("Head", tube(L.tier + "Rim", rim_pts, 0.05, L.cloth, closed=True, sides=10))
    # thick forehead band all round the hood, just above the window
    band = [(1.98, 0.785, 0.765), (2.02, 0.795, 0.775), (2.16, 0.775, 0.755), (2.22, 0.745, 0.725)]
    L.add("Head", S.lofted(L.tier + "Brim", [(z, hx, hy, 0.0, -0.02) for z, hx, hy in band], style.get("brim", L.cloth), power=3.6, n=64))
    # mask: wraps the lower head, bulging in front, a point over the nose, sagging folds
    stations = []
    prof = ((0.98, 0.7, 0.66, 0.0), (1.06, 0.79, 0.74, 0.03), (1.22, 0.82, 0.8, 0.05), (1.38, 0.81, 0.8, 0.05), (1.5, 0.795, 0.77, 0.03), (1.56, 0.78, 0.74, 0.02))
    for i in range(len(prof) - 1):
        a0, a1 = prof[i], prof[i + 1]
        for k in range(4):
            t = k / 4
            stations.append(tuple(a0[j] + (a1[j] - a0[j]) * t for j in range(4)))
    stations.append(prof[-1])
    mask = S.lofted(L.tier + "Mask", [(z, hx, hy, 0.0, cy) for z, hx, hy, cy in stations], L.cloth, power=2.6, n=64)
    top = max(v.co.z for v in mask.data.vertices)
    for v in mask.data.vertices:
        if v.co.z > top - 1e-4 and v.co.y > 0:
            v.co.z -= 0.13 * min(1.0, abs(v.co.x) / 0.55) * min(1.0, v.co.y / 0.4)

    def drape(co, n):
        if co.y < 0.05:
            return 0.0
        u = min(1.0, abs(co.x) / 0.8)
        env = min(1.0, (co.y - 0.05) / 0.3)
        z = co.z + 0.2 * (1 - u * u)
        folds = 0.028 * math.sin(z * 15 + 1.2) * (0.3 + 0.7 * math.sin(min(1.0, max(0.0, (1.55 - co.z) / 0.55)) * math.pi))
        bunch = 0.025 * max(0.0, u - 0.55) / 0.45 * math.sin(co.z * 40)
        return env * (folds + bunch + 0.03 * (1 - u * u))
    displace(mask, drape)
    L.add("Head", mask)
    if style.get("band"):
        L.add("Head", rbox(L.tier + "Band", (0.745, 0.745, 0.13), (0, 0.0, 2.1), L.cloth, power=5))
        knot = rbox(L.tier + "BandKnot", (0.16, 0.12, 0.12), (0, -0.74, 2.1), L.cloth, power=3)
        L.add("Head", knot)
        for side in (-1, 1):
            tail = rbox(L.tier + "BandTail%d" % side, (0.08, 0.05, 0.22), (side * 0.12, -0.76, 1.9), L.cloth, power=3)
            tail.rotation_euler = (0, side * 0.35, 0)
            C.apply_transforms([tail])
            L.add("Head", tail)
    if style.get("seam"):
        for sx in (-0.36, 0.36):
            pts = []
            for i in range(30):
                y = 0.62 - i * 1.3 / 29
                p, n = hit(hood, (sx, y, 4), (0, 0, -1))
                if p and p.z > 2.22:
                    pts.append(p + n * 0.006)
            L.add("Head", tube(L.tier + "Seam%d" % (sx > 0), pts, 0.028, L.cloth, sides=8))
            for i, p in enumerate(pts[1:-1]):
                _, n = hit(hood, p + Vector((0, 0, 1)), (0, 0, -1))
                side = n.cross(Vector((0, 1, 0))).normalized() if n else Vector((1, 0, 0))
                L.add("Head", strip(L.tier + "Stitch%d%d" % (i, sx > 0), [(p - side * 0.05, n), (p + side * 0.05, n)], 0.018, 0.008, L.dark, lift=0.01, bevel=0))
    # eyes
    if style["eyes"] == "ink":
        for side in (-1, 1):
            s = side
            brow = [(s * 0.53, 1.92), (s * 0.45, 1.99), (s * 0.25, 1.92), (s * 0.08, 1.81), (s * 0.05, 1.74), (s * 0.12, 1.76), (s * 0.27, 1.84), (s * 0.47, 1.88)]
            eye = [(s * 0.29, 1.84), (s * 0.18, 1.75), (s * 0.23, 1.55), (s * 0.34, 1.73)]
            L.add("Head", flat_shape(L.tier + "Brow%d" % side, brow, 0.59, L.ink, hood))
            L.add("Head", flat_shape(L.tier + "Eye%d" % side, eye, 0.59, L.ink, hood))
    elif style["eyes"] == "demon":
        # angry glowing slits under a heavy brow (hero_demons.py)
        for side in (-1, 1):
            s = side
            brow = [(s * 0.55, 1.95), (s * 0.47, 2.0), (s * 0.26, 1.9), (s * 0.06, 1.79), (s * 0.04, 1.71), (s * 0.13, 1.73), (s * 0.3, 1.82), (s * 0.5, 1.89)]
            L.add("Head", flat_shape(L.tier + "Brow%d" % side, brow, 0.59, style.get("brow", L.ink), hood, thick=0.03))
            socket = [(s * 0.08, 1.75), (s * 0.47, 1.87), (s * 0.45, 1.68), (s * 0.16, 1.63)]
            L.add("Head", flat_shape(L.tier + "Socket%d" % side, socket, 0.59, L.ink, hood, thick=0.014))
            slit = [(s * 0.13, 1.735), (s * 0.43, 1.83), (s * 0.41, 1.71), (s * 0.19, 1.665)]
            L.glow["Head"].append(flat_shape(L.tier + "Eye%d" % side, slit, 0.59, style["glow"], hood, thick=0.03))
    else:
        gem_mat = style["gem_mat"]
        for side in (-1, 1):
            s = side
            brow = [(s * 0.53, 1.92), (s * 0.45, 1.99), (s * 0.25, 1.92), (s * 0.08, 1.81), (s * 0.05, 1.74), (s * 0.12, 1.76), (s * 0.27, 1.84), (s * 0.47, 1.88)]
            L.add("Head", flat_shape(L.tier + "Brow%d" % side, brow, 0.59, style.get("brow", L.ink), hood, thick=0.02))
            outline = [(s * 0.1, 1.78), (s * 0.17, 1.84), (s * 0.37, 1.84), (s * 0.44, 1.78), (s * 0.27, 1.56)]
            L.add("Head", flat_shape(L.tier + "EyeRim%d" % side, outline, 0.59, L.ink, hood))
            L.glow["Head"].append(gem_eye(L.tier + "Gem%d" % side, s * 0.27, 1.73, 0.28, 0.21, gem_mat, hood, side))
    return hood


def lateral(samples, offset, lift):
    """The same surface path shifted sideways (in-surface) by offset and out by lift."""
    out = []
    n = len(samples)
    for i, (p, nrm) in enumerate(samples):
        t = (samples[min(i + 1, n - 1)][0] - samples[max(i - 1, 0)][0]).normalized()
        a = nrm.cross(t).normalized()
        out.append((p + a * offset + nrm * lift, nrm))
    return out


def dashes(name, samples, mat, width=0.022, thick=0.01, dash=0.06, gap=0.045):
    """Stitch dashes along a surface path (gold stitching on the blue gear)."""
    out = []
    acc, on, cur = 0.0, True, [samples[0]]
    for (p0, n0), (p1, n1) in zip(samples, samples[1:]):
        seg = (p1 - p0).length
        acc += seg
        cur.append((p1, n1))
        if acc >= (dash if on else gap):
            if on and len(cur) >= 2:
                out.append(strip("%s%d" % (name, len(out)), [cur[0], cur[-1]], width, thick, mat, lift=0.002, bevel=0))
            on, acc, cur = not on, 0.0, [(p1, n1)]
    return out


def path_on(target, pts_v, step=0.05, back=False):
    """Dense surface samples along a viewer-space polyline on target's front."""
    out = []
    for i in range(len(pts_v) - 1):
        (a0, b0), (a1, b1) = pts_v[i], pts_v[i + 1]
        steps = max(2, int(math.hypot(a1 - a0, b1 - b0) / step))
        for k in range(steps + (1 if i == len(pts_v) - 2 else 0)):
            t = k / steps
            p, n = front(target, a0 + (a1 - a0) * t, b0 + (b1 - b0) * t, back)
            if p:
                out.append((p, n))
    return out


def rect_loop(target, cx, cz, hw, hh, step=0.05):
    return path_on(target, [(cx - hw, cz + hh), (cx + hw, cz + hh), (cx + hw, cz - hh), (cx - hw, cz - hh), (cx - hw, cz + hh)], step)


def torso(L, style):
    jacket = L.add("UpperTorso", rbox(L.tier + "Jacket", (1.02, 0.53, 0.86), (0, 0, 0.16), L.cloth, power=14, segs=48, rings=32))
    # V neck showing the undershirt / skin
    v = [(-0.34, 1.2), (0.34, 1.2), (0.0, 0.42)]
    vcut = C.extrude_outline(L.tier + "VNeck", [(-vx, z) for vx, z in v], 0.3, style.get("vneck", L.dark), axis="Y")
    vcut.location = (0, 0.53 + 0.11, 0)
    C.apply_transforms([vcut])
    cut(jacket, vcut)

    def over_shoulder(vx):
        out = []
        for i in range(8):
            y = 0.45 - i * 0.12
            p, n = hit(jacket, (-vx, y, 3), (0, 0, -1))
            if p:
                out.append((p, n))
        return out
    lw = style.get("lapel_w", 0.3)
    inner = over_shoulder(-0.46)[::-1] + path_on(jacket, [(-0.46, 1.0), (-0.2, 0.5), (0.12, 0.12)], 0.06)
    outer = over_shoulder(0.46)[::-1] + path_on(jacket, [(0.46, 1.0), (0.16, 0.46), (-0.2, 0.08), (-0.48, -0.28), (-0.56, -0.6)], 0.06)
    L.add("UpperTorso", strip(L.tier + "LapelIn", inner, lw, 0.07, L.trim, bevel=0.5))
    collar = style.get("collar", L.dark)
    if collar is not None:
        for side in (-1, 1):
            L.add("UpperTorso", strip(L.tier + "Collar%d" % side, path_on(jacket, [(side * 0.26, 0.98), (0.0, 0.46)], 0.06), 0.12, 0.04, collar, bevel=0.4))
    L.add("UpperTorso", strip(L.tier + "LapelOut", outer, lw, 0.08, L.trim, lift=0.035, bevel=0.5))
    L.lapels = (inner, outer, lw)
    if style.get("stitch"):
        for k, (path, lift) in enumerate(((outer, 0.035 + 0.08), (inner, 0.07))):
            for side in (-1, 1):
                for o in dashes(L.tier + "LapSt%d%d_" % (k, side), lateral(path, side * lw * 0.33, lift), style["stitch"]):
                    L.add("UpperTorso", o)
    if style.get("emblem"):
        for k in range(3):
            pts = path_on(jacket, [(0.36 + k * 0.08, 0.72), (0.48 + k * 0.08, 0.92)], 0.03)
            L.add("UpperTorso", strip(L.tier + "Claw%d" % k, pts, 0.035, 0.012, style["emblem"], lift=0.002, bevel=0,
                                      taper=lambda t: 0.3 + 0.7 * math.sin(t * math.pi)))
    return jacket


def hips(L, style):
    skirt = L.add("LowerTorso", rbox(L.tier + "Skirt", (1.035, 0.55, 0.27), (0, 0, -0.78), L.cloth, power=14, segs=48, rings=16))
    flap = []
    for i in range(8):
        z = -0.62 - i * 0.06
        p, n = front(skirt, -0.62 + i * 0.01, z)
        if p:
            flap.append((p, n))
    L.add("LowerTorso", strip(L.tier + "Flap", flap, 0.26, 0.06, L.trim, lift=0.01, bevel=0.45))
    kind = style["belt"]
    if kind == "blue":
        belt = L.add("LowerTorso", rbox(L.tier + "Sash", (1.07, 0.585, 0.1), (0, 0, -0.5), style["sash"], power=14, segs=48, rings=12))
        L.add("LowerTorso", rbox(L.tier + "Belt", (1.08, 0.595, 0.075), (0, 0, -0.66), L.trim, power=14, segs=48, rings=12))
    else:
        belt = L.add("LowerTorso", rbox(L.tier + "Belt", (1.07, 0.585, 0.11), (0, 0, -0.62), L.trim, power=14, segs=48, rings=12))
    fy = 0.585
    if kind == "buckle":
        c = Vector((0, fy + 0.01, -0.6))
        for (sx, sz, px, pz) in ((0.3, 0.05, 0, 0.1), (0.3, 0.05, 0, -0.1), (0.05, 0.25, 0.125, 0), (0.05, 0.25, -0.125, 0)):
            L.add("LowerTorso", C.box(L.tier + "Buckle%.2f%.2f" % (px, pz), (sx, 0.05, sz), (c.x + px, c.y, c.z + pz), L.metal, bevel=0.012))
        L.add("LowerTorso", C.box(L.tier + "BuckleIn", (0.2, 0.02, 0.15), (0, c.y - 0.01, c.z), L.metal_dark))
        for dx, ang, ln in ((-0.04, 0.12, 0.34), (0.07, -0.18, 0.3)):
            t = C.box(L.tier + "Tail%.2f" % dx, (0.13, 0.04, ln), (dx, fy + 0.02, -0.72 - ln / 2), L.trim, bevel=0.015)
            t.rotation_euler = (0, ang, 0)
            C.apply_transforms([t])
            L.add("LowerTorso", t)
    elif kind == "knot":
        L.add("LowerTorso", rbox(L.tier + "Knot", (0.14, 0.07, 0.13), (0, fy + 0.03, -0.62), L.trim, power=6))
        L.add("LowerTorso", C.box(L.tier + "KnotIn", (0.13, 0.02, 0.11), (0, fy + 0.095, -0.62), L.trim, bevel=0.012))
        for side, ang in ((-1, -0.35), (1, 0.4)):
            t = rbox(L.tier + "Tail%d" % side, (0.07, 0.035, 0.25), (0, 0, 0), L.trim, power=6)
            t.rotation_euler = (0, ang * side * -1, 0)
            t.location = (side * -0.1, fy + 0.05, -0.95)
            C.apply_transforms([t])
            L.add("LowerTorso", t)
    elif kind == "blue":
        gold, gem = style["gold"], style["gem"]
        for i in range(-9, 10):
            if abs(i) <= 2:
                continue
            vx = i * 0.1
            p, n = front(belt, vx, -0.66)
            if p:
                L.add("LowerTorso", S.ellipsoid(L.tier + "Stud%d" % i, (0.022, 0.022, 0.022), p + n * 0.075, gold, segs=8, rings=6))
        L.add("LowerTorso", rbox(L.tier + "Buckle", (0.2, 0.05, 0.1), (0, 0.65, -0.66), gold, power=6))
        L.add("LowerTorso", rbox(L.tier + "BuckleIn", (0.14, 0.05, 0.065), (0, 0.67, -0.66), style["sash"], power=6))
        L.glow["LowerTorso"].append(S.ellipsoid(L.tier + "BuckleGem", (0.07, 0.04, 0.05), (0, 0.72, -0.66), gem, power=1.3, segs=4, rings=4))
        # hip pouches with gold-trimmed flaps
        for side in ((-1, 1) if style.get("pouches", True) else ()):
            cx = side * 0.72
            L.add("LowerTorso", rbox(L.tier + "Pouch%d" % side, (0.16, 0.1, 0.15), (cx, 0.62, -0.86), L.trim, power=8))
            flap_ = rbox(L.tier + "PouchFlap%d" % side, (0.17, 0.11, 0.07), (cx, 0.635, -0.76), L.trim, power=8)
            L.add("LowerTorso", flap_)
            L.add("LowerTorso", tube(L.tier + "PouchTrim%d" % side, [(cx - 0.15, 0.745, -0.72), (cx - 0.15, 0.745, -0.8), (cx + 0.15, 0.745, -0.8), (cx + 0.15, 0.745, -0.72)], 0.012, gold, sides=6))
        # bandolier: silver and blue segments from the buckle down to the right hip (viewer's right)
        bpath = path_on(skirt, [(0.18, -0.74), (0.5, -0.88), (0.62, -1.0)], 0.02) if style.get("bandolier", True) else [None]
        acc, cur, k = 0.0, [bpath[0]], 0
        for (p0, n0), (p1, n1) in zip(bpath, bpath[1:]):
            acc += (p1 - p0).length
            cur.append((p1, n1))
            if acc >= 0.07:
                mat = L.metal if k % 2 == 0 else style["sash"]
                L.add("LowerTorso", strip(L.tier + "Band%d" % k, [cur[0], cur[-1]], 0.1, 0.03, mat, lift=0.02, bevel=0.2))
                k, acc, cur = k + 1, 0.0, [(p1, n1)]
        # tassels on the right hip
        for i, dz in enumerate((0.0, -0.08) if style.get("tassels", True) else ()):
            cx = -0.86 + i * 0.1
            L.add("LowerTorso", tube(L.tier + "Cord%d" % i, [(cx, 0.6, -0.7), (cx, 0.62, -0.95 + dz)], 0.012, style["sash"], sides=6))
            t = C.lathe(L.tier + "Tassel%d" % i, [(0.001, 0.0), (0.03, -0.03), (0.045, -0.2), (0.001, -0.21)], 10, L.metal, axis="Z", smooth=True)
            t.location = (cx, 0.62, -0.95 + dz)
            C.apply_transforms([t])
            L.add("LowerTorso", t)
    return skirt


def arm(L, style):
    x = 1.43
    if style.get("armored"):
        gold = style.get("stitch")
        L.add("RightUpperArm", rbox(L.tier + "UpperSkin", (0.38, 0.44, 0.5), (x, 0, 0.55), L.skin, power=14))
        for i, (z, hx, hz, tilt) in enumerate(((0.94, 0.44, 0.13, 0.18), (0.74, 0.46, 0.12, 0.3)) if style.get("pads", True) else ()):
            pad = rbox(L.tier + "Pad%d" % i, (hx, 0.52 + i * 0.01, hz), (0, 0, 0), L.cloth, power=8)
            pad.rotation_euler = (0, -tilt, 0)
            pad.location = (x + 0.03 + i * 0.04, 0, z)
            C.apply_transforms([pad])
            L.add("RightUpperArm", pad)
            pts = []
            for k in range(13):
                y = -0.5 + k * (1.0 / 12)
                p, n = hit(pad, (x + 0.03 + i * 0.04 + 2.0, y, z - 0.1 - i * 0.02), (-1, 0, 0))
                if p:
                    pts.append((p, n))
            for o in dashes(L.tier + "PadSt%d_" % i, lateral(pts, 0, 0.004), gold):
                L.add("RightUpperArm", o)
        L.add("RightLowerArm", rbox(L.tier + "ForeSkin", (0.37, 0.43, 0.44), (x, 0, -0.29), L.skin, power=14))
        br = L.add("RightLowerArm", rbox(L.tier + "Bracer", (0.43, 0.49, 0.3), (x, 0, -0.42), style.get("bracer", L.cloth), power=12))
        for i, z in enumerate((-0.25, -0.55)):
            L.add("RightLowerArm", rbox(L.tier + "Strap%d" % i, (0.445, 0.505, 0.05), (x, 0, z), style["sash"], power=12))
        for zz in ((-0.16, -0.68) if gold else ()):
            pts = []
            for k in range(25):
                a = math.tau * k / 24
                p, n = hit(br, (x + math.cos(a) * 2, math.sin(a) * 2, zz), (-math.cos(a), -math.sin(a), 0))
                if p:
                    pts.append((p, n))
            for o in dashes(L.tier + "BrSt%.2f_" % zz, pts, gold):
                L.add("RightLowerArm", o)
        hand = rbox(L.tier + "Hand", (0.39, 0.44, 0.19), (x, 0, -0.9), L.skin, power=14)
        slot = C.box(L.tier + "HandSlot", (0.5, 1.2, 0.13), (x - 0.24, 0, -0.93), L.skin)
        cut(hand, slot)
        L.add("RightHand", hand)
        return
    up = L.add("RightUpperArm", rbox(L.tier + "Sleeve", (0.41, 0.47, 0.5), (x, 0, 0.55), L.cloth, power=14))
    displace(up, ring_folds(0.08, 0.4, 3, 0.018))
    lo = L.add("RightLowerArm", rbox(L.tier + "Forearm", (0.405, 0.465, 0.44), (x, 0, -0.29), L.cloth, power=14))
    displace(lo, ring_folds(-0.1, 0.15, 2, 0.015))
    if style.get("cuff"):
        L.add("RightLowerArm", rbox(L.tier + "Cuff", (0.43, 0.49, 0.09), (x, 0, -0.65), L.cloth, power=14))
    L.add("RightHand", rbox(L.tier + "Hand", (0.39, 0.44, 0.17), (x, 0, -0.88), L.skin, power=14))


def leg(L, style):
    x = 0.49
    th = L.add("RightUpperLeg", rbox(L.tier + "Thigh", (0.46, 0.5, 0.5), (x, 0, -1.47), L.cloth, power=14))
    displace(th, ring_folds(-1.95, -1.7, 2, 0.012))
    L.add("RightLowerLeg", rbox(L.tier + "Shin", (0.455, 0.49, 0.34), (x, 0, -2.2), L.cloth, power=14))
    L.add("RightFoot", rbox(L.tier + "Boot", (0.48, 0.56, 0.28), (x, 0.05, -2.72), L.boot, power=5))
    if style.get("wraps"):
        wrap = L.add("RightLowerLeg", rbox(L.tier + "ShinWrap", (0.475, 0.51, 0.24), (x, 0, -2.22), L.trim, power=12))
        for i, zc in enumerate((-2.06, -2.28)):
            for d in (-1, 1):
                pts = path_on(wrap, [(-x - 0.07, zc + d * 0.06), (-x + 0.07, zc - d * 0.06)], 0.02)
                L.add("RightLowerLeg", strip(L.tier + "X%d%d" % (i, d), pts, 0.025, 0.012, style["x"], lift=0.002, bevel=0))
        ring = [(x + math.cos(a) * 0.5, math.sin(a) * 0.55 + 0.02, -2.47) for a in [math.tau * k / 32 for k in range(32)]]
        L.add("RightFoot", tube(L.tier + "Rope", ring, 0.035, style["sash"], closed=True))
        for d in (-1, 1):
            L.add("RightFoot", tube(L.tier + "RopeTie%d" % d, [(x + d * 0.03, 0.58, -2.47), (x + d * 0.12, 0.62, -2.55)], 0.03, style["sash"]))


# ---------------------------------------------------------------- tiers
def brown():
    L = Look("brown", (134, 72, 36), (150, 84, 44), (80, 42, 20), (118, 62, 30))
    head(L, {"eyes": "ink", "seam": True})
    torso(L, {})
    hips(L, {"belt": "buckle"})
    arm(L, {})
    leg(L, {})
    return L


def green():
    L = Look("green", (52, 150, 58), (58, 162, 64), (26, 90, 32), (48, 140, 54), streaks=0.06)
    gem = H.paint("greenGem", (60, 235, 90), roughness=0.1, emission=1.5, roblox="Neon")
    brow = H.paint("greenBrow", (40, 130, 46), roughness=0.5)
    head(L, {"eyes": "gem", "gem_mat": gem, "brow": brow, "brim": L.cloth})
    torso(L, {"vneck": L.skin, "collar": None})
    hips(L, {"belt": "knot"})
    arm(L, {"cuff": True})
    leg(L, {})
    return L


def blue():
    L = Look("blue", (26, 74, 186), (30, 84, 198), (14, 28, 74), (24, 68, 176))
    gold = H.paint("blueGold", (232, 184, 70), noise=0.05, roughness=0.3, roblox="Metal")
    sash = H.paint("blueSash", (22, 40, 96), noise=0.08, scale=22, roblox="Fabric")
    gem = H.paint("blueGem", (70, 190, 255), roughness=0.1, emission=1.5, roblox="Neon")
    steel = H.paint("blueSteel", (120, 150, 200), roughness=0.3)
    head(L, {"eyes": "gem", "gem_mat": gem, "brow": L.ink, "brim": L.cloth})
    torso(L, {"vneck": L.skin, "collar": sash, "stitch": gold, "emblem": steel})
    hips(L, {"belt": "blue", "gold": gold, "sash": sash, "gem": gem})
    arm(L, {"armored": True, "stitch": gold, "sash": sash})
    leg(L, {"wraps": True, "x": gold, "sash": sash})
    return L


# ---------------------------------------------------------------- higher tiers (purple .. void)
# Built on the same body as blue, escalating per tier: purple shoulder domes + crest,
# red samurai plates, black stealth with lit seams, white frost/moon with a cape, gold
# ornate armour, crimson oni horns + demon mask, shadow tatters + wisps, celestial
# stars + halo, void cosmic cracks + horns + eclipse. Everything glowing goes in the
# __Glow meshes, which the game shows as Neon in the tier's Color (Tiers.lua).
GLOW = {
    "purple": (170, 90, 255), "red": (255, 70, 60), "black": (70, 70, 80), "white": (235, 245, 255),
    "gold": (255, 200, 50), "crimson": (220, 20, 60), "shadow": (130, 80, 220), "celestial": (140, 210, 255),
    "void": (200, 60, 255),
}


class Tier(Look):
    def __init__(self, tier, cloth, trim, dark, boot, **kw):
        super().__init__(tier, cloth, trim, dark, boot, **kw)
        self.glowm = H.paint(tier + "Glow", GLOW[tier], roughness=0.2, emission=2.2, roblox="Neon")
        self.n = 0

    def lit(self, region, o):
        self.glow[region].append(o)
        return o

    def uid(self, base):
        self.n += 1
        return "%s%s%d" % (self.tier, base, self.n)


def sheen(name, color, lo=0.6, hi=1.35, noise=0.04, roblox="Metal"):
    """Lacquer / metal: the colour is lit from above in the bake (brighter on top faces,
    darker underneath) so plates read as polished even on a flat-shaded texture."""
    mat = H.paint(name, color, noise=noise, scale=14, roughness=0.3, roblox=roblox)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    links = bsdf.inputs["Base Color"].links
    base = links[0].from_socket if links else None
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs[0])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -1.0
    mr.inputs["From Max"].default_value = 1.0
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, (lo, lo, lo, 1)
    els[1].position, els[1].color = 1.0, (hi, hi, hi, 1)
    mid = els.new(0.55)
    mid.color = (1, 1, 1, 1)
    nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    if base is not None:
        nt.links.new(base, mul.inputs["A"])
    else:
        mul.inputs["A"].default_value = (*C.rgb(*color), 1)
    nt.links.new(ramp.outputs["Color"], mul.inputs["B"])
    nt.links.new(mul.outputs["Result"], bsdf.inputs["Base Color"])
    return mat


def cloth(name, color, noise=0.08, streaks=0.1):
    return H.paint(name, color, noise=noise, scale=22, streaks=streaks, roblox="Fabric")


def named(L, region, suffix):
    return next(o for o in L.parts[region] if o.name == L.tier + suffix)


def drop(L, region, suffix):
    o = named(L, region, suffix)
    L.parts[region].remove(o)
    bpy.data.objects.remove(o)


def xform(objs, M):
    for o in objs:
        o.data.transform(M)
        o.data.update()


def about(angle, axis, pivot):
    pv = Vector(pivot)
    return Matrix.Translation(pv) @ Matrix.Rotation(angle, 4, axis) @ Matrix.Translation(-pv)


def taper_tube(name, pts, radii, mat, sides=10):
    """Solid tapering along 3D points ending in a point (horns, spikes, wisps)."""
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
        ring = []
        for k in range(sides):
            ang = math.tau * k / sides
            ring.append(len(verts))
            verts.append(p + (a * math.cos(ang) + b * math.sin(ang)) * radii[i])
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


def horn_curve(base, direction, length, radius, bend=(0, 0, 0), twist=0.0, steps=12, ridges=0.0):
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
    return pts, radii


def horn(name, base, direction, length, radius, mat, tip_mat=None, tip=0.3, sides=12, **kw):
    """Curved tapering horn; with tip_mat the last `tip` of it is a separate piece
    (returned second) so it can glow."""
    pts, radii = horn_curve(base, direction, length, radius, **kw)
    if tip_mat is None:
        return taper_tube(name, pts, radii, mat, sides), None
    k = max(2, int(len(pts) * (1 - tip)))
    body = taper_tube(name, pts[:k + 1], radii[:k + 1], mat, sides)
    end = taper_tube(name + "Tip", pts[k - 1:], [r * 1.04 for r in radii[k - 1:]], tip_mat, sides)
    return body, end


def fang(name, p, n, length, width, mat, down=(0, 0, -1)):
    n = Vector(n).normalized()
    dn = Vector(down).normalized()
    side = n.cross(dn)
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side.normalize()
    base = Vector(p)
    verts = [base - side * width / 2, base + side * width / 2, base + side * width / 2 + n * width * 0.45,
             base - side * width / 2 + n * width * 0.45, base + dn * length + n * width * 0.25]
    faces = [(0, 1, 2, 3), (0, 4, 1), (1, 4, 2), (2, 4, 3), (3, 4, 0)]
    return H.flat(name, verts, faces, mat)


def catmull(ctrl, per=6):
    pts = [Vector(p) for p in ctrl]
    out = []
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        for k in range(per):
            t = k / per
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(pts[-1])
    return out


def ribbon(name, ctrl, side, width, thick, mat, taper=None, per=6, bevel=0.3):
    """Flat cloth band through a smooth curve; its width runs along `side` (scarf
    tails, hood tails, rags)."""
    pts = catmull(ctrl, per)
    n = len(pts)
    samples = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        samples.append((p, t.cross(Vector(side)).normalized()))
    return strip(name, samples, width, thick, mat, lift=0.0, bevel=bevel, taper=taper)


def decal(name, outline, p, n, mat, thick=0.015, lift=0.004, up=(0, 0, 1)):
    """Thin plate of a 2D outline [(u, v)] laid on a surface point p with normal n
    (u runs to the viewer's right when looking at the surface, v up)."""
    n = Vector(n).normalized()
    upv = Vector(up)
    if abs(upv.dot(n)) > 0.95:
        upv = Vector((0, 1, 0)) if abs(n.y) < 0.95 else Vector((0, 0, 1))
    a = upv.cross(n).normalized()
    b = n.cross(a).normalized()
    verts = []
    for w in (lift, lift + thick):
        for u, v in outline:
            verts.append(Vector(p) + a * u + b * v + n * w)
    k = len(outline)
    o = H.flat(name, verts, C.loft([list(range(k)), list(range(k, 2 * k))]), mat)
    return o


def star_outline(r, points=4, inner=0.38, rot=0.0, cx=0.0, cz=0.0):
    out = []
    for k in range(points * 2):
        a = rot + math.pi / 2 + k * math.pi / points
        rr = r if k % 2 == 0 else r * inner
        out.append((cx + math.cos(a) * rr, cz + math.sin(a) * rr))
    return out


def crescent_outline(r, rot=0.5, steps=14):
    """Crescent moon (two circle arcs), horns pointing towards +u rotated by rot."""
    d, r2 = 0.45, 0.82
    pts = []
    a0, a1 = math.radians(53.9), math.radians(80.2)
    for k in range(steps + 1):
        a = a0 + (math.tau - 2 * a0) * k / steps
        pts.append((math.cos(a), math.sin(a)))
    for k in range(steps + 1):
        a = (math.tau - a1) - (math.tau - 2 * a1) * k / steps
        pts.append((d + r2 * math.cos(a), r2 * math.sin(a)))
    c, s = math.cos(rot), math.sin(rot)
    return [((x * c - y * s) * r, (x * s + y * c) * r) for x, y in pts[:-1]]


def diamond(w, h):
    return [(0, h), (w, 0), (0, -h), (-w, 0)]


def walk(target, p, n, d, steps, step, rnd, zig=0.6, drift=0.15):
    """Jagged path over a surface from p heading d (cracks, lightning seams)."""
    pts = [(p, n)]
    sign = 1 if rnd.random() < 0.5 else -1
    d = Vector(d)
    for _ in range(steps):
        d = d - n * d.dot(n)
        if d.length < 1e-6:
            break
        d.normalize()
        d = Matrix.Rotation(rnd.uniform(-drift, drift), 3, n) @ d
        heading = Matrix.Rotation(sign * rnd.uniform(0.15, zig), 3, n) @ d if zig else d
        sign = -sign
        q = p + heading * step
        hp, hn = hit(target, q + n * 0.25, -n)
        if hp is None or (hp - p).length > step * 2.5 or (hp - p).length < step * 0.3:
            break
        p, n = hp, hn
        pts.append((p, n))
    return pts


def crack(L, region, target, origin, direction, rnd, length=0.6, width=0.04, branches=2, heading=None, step=0.05, zig=0.65):
    """Neon crack: a jagged glowing line over target's surface, with side branches."""
    p, n = hit(target, origin, direction)
    if p is None:
        return []
    d = Vector(heading) if heading else Matrix.Rotation(rnd.uniform(0, math.tau), 3, n) @ n.orthogonal()
    path = walk(target, p, n, d, int(length / step), step, rnd, zig=zig)
    out = []
    if len(path) >= 3:
        out.append(L.lit(region, strip(L.uid("Crack"), path, width, 0.016, L.glowm, lift=0.004, bevel=0, taper=lambda t: max(0.2, 1 - 0.8 * t))))
        for _ in range(branches):
            i = rnd.randrange(1, len(path) - 1)
            q, m = path[i]
            dd = (path[i + 1][0] - q)
            dd = Matrix.Rotation(rnd.choice((-1, 1)) * rnd.uniform(0.5, 1.0), 3, m) @ dd
            sub = walk(target, q, m, dd, int(length * 0.45 / step), step, rnd, zig=zig)
            if len(sub) >= 3:
                out.append(L.lit(region, strip(L.uid("Crack"), sub, width * 0.6, 0.014, L.glowm, lift=0.004, bevel=0, taper=lambda t: max(0.2, 1 - 0.8 * t))))
    return out


def seam(L, region, target, origin, direction, heading, length, width=0.03, mat=None):
    """Straight lit line over a surface (glowing seams)."""
    p, n = hit(target, origin, direction)
    if p is None:
        return None
    path = walk(target, p, n, Vector(heading), int(length / 0.04), 0.04, random.Random(1), zig=0, drift=0)
    if len(path) < 2:
        return None
    o = strip(L.uid("Seam"), path, width, 0.014, mat or L.glowm, lift=0.004, bevel=0)
    return L.lit(region, o) if mat is None else L.add(region, o)


def jag_tail(name, top, width, length, mat, points=3, thick=0.03, tilt=0.0, seed=0, yaw=0.0):
    """Torn cloth strip hanging from top (x, y, z), its bottom ripped into points."""
    x0, y0, z0 = top
    outline = [(-width / 2, 0), (width / 2, 0)]
    rnd = random.Random(seed)
    for k in range(points * 2 + 1):
        u = 1 - k / (points * 2)
        depth = length * (1.0 if k % 2 == 0 else 0.7) * rnd.uniform(0.85, 1.05)
        outline.append((-width / 2 + width * u, -depth))
    o = C.extrude_outline(name, outline, thick, mat, axis="Y")
    o.rotation_euler = (tilt, 0, yaw)
    o.location = (x0, y0, z0)
    C.apply_transforms([o])
    return o


def shell(name, mat, z0, z1, hx, hy, cx, cy=0.0, power=3.2, n=40, profile=3.0):
    """Dome (half superellipsoid) from z0 up to z1: pauldrons, helmet caps."""
    st = []
    for k in range(9):
        t = 0.985 * (k / 8) ** 0.8
        s = (1 - t ** profile) ** (1 / profile)
        st.append((z0 + (z1 - z0) * t, hx * s, hy * s, cx, cy))
    return S.lofted(name, st, mat, power=power, n=n)


def ring_pts(cx, cy, z, rx, ry, power=2.0, n=40):
    out = []
    for k in range(n):
        a = math.tau * k / n
        c, s = math.cos(a), math.sin(a)
        out.append((cx + rx * math.copysign(abs(c) ** (2 / power), c), cy + ry * math.copysign(abs(s) ** (2 / power), s), z))
    return out


def lathe_disc(name, r, th, center, mat, facing=1, segs=28, bevel=0.85):
    """Coin facing +Y (facing=1) or -Y with a bevelled face."""
    o = C.lathe(name, [(0.001, 0.0), (r, 0.0), (r, th * 0.6), (r * bevel, th), (0.001, th)], segs, mat, axis="Y")
    if facing < 0:
        o.data.transform(Matrix.Scale(-1, 4, (0, 1, 0)))
        o.data.flip_normals()
    o.data.transform(Matrix.Translation(Vector(center)))
    return o


def medallion(L, region, target, vx, z, r, ring, inner_shape, inner_mat=None, back=False, glow=True, rim=None):
    """Raised coin on target's front (or back) with a shape on it (glowing by default)."""
    p, n = front(target, vx, z, back)
    s = -1 if back else 1
    L.add(region, lathe_disc(L.uid("Medal"), r, 0.05, (p.x, p.y - s * 0.012, p.z), ring, facing=s))
    if rim is not None:
        ring_ = [(p.x + math.cos(a) * r * 0.98, p.y + s * 0.035, p.z + math.sin(a) * r * 0.98) for a in [math.tau * k / 28 for k in range(28)]]
        L.add(region, tube(L.uid("MedalRim"), ring_, 0.016, rim, closed=True, sides=6))
    q = Vector((p.x, p.y + s * 0.04, p.z))
    shp = decal(L.uid("MedalShape"), inner_shape, q, Vector((0, s, 0)), inner_mat or L.glowm, thick=0.02)
    if glow and inner_mat is None:
        L.lit(region, shp)
    else:
        L.add(region, shp)
    return p


def cape(L, outer, lining, hem, width=0.84, top=0.98, bottom=-1.72, flare=0.34, spread=0.22, jag=0.0, teeth=5,
         rag=0.0, folds=3.5, seed=1, hem_glow=False, nu=26, nv=22, hem_r=0.03):
    """Cape hanging from the shoulders (UpperTorso), flaring back, optional torn hem."""
    rnd = random.Random(seed)
    seg = [rnd.uniform(1 - rag, 1 + rag * 0.3) for _ in range(teeth)]

    def zb(u):
        if not jag:
            return bottom
        f = u * teeth
        k = min(int(f), teeth - 1)
        tri = abs((f - k) - 0.5) * 2
        return bottom - jag * (1 - tri) * seg[k]

    def pos(u, t, dy=0.0):
        s = 2 * u - 1
        x = s * width * (1 + spread * t)
        y = -0.575 - flare * t ** 1.6 - 0.05 * t * math.sin(s * math.pi * folds + 0.6) - 0.03 * (1 - s * s) * t + dy
        z = top + (zb(u) - top) * t
        return (x, y, z)

    def sheet(name, mat, dy, thick):
        verts, faces = [], []
        for j in range(nv + 1):
            for i in range(nu + 1):
                verts.append(pos(i / nu, j / nv, dy))
        for j in range(nv):
            for i in range(nu):
                a = j * (nu + 1) + i
                faces.append((a, a + 1, a + nu + 2, a + nu + 1))
        o = C.mesh_object(name, verts, faces, mat, smooth=True)
        m = o.modifiers.new("Solid", "SOLIDIFY")
        m.thickness = thick
        m.offset = 0.0
        C.apply_modifiers(o)
        C.recalc_normals(o)
        return o
    out = L.add("UpperTorso", sheet(L.tier + "Cape", outer, 0.0, 0.035))
    if lining is not None:
        L.add("UpperTorso", sheet(L.tier + "CapeLining", lining, 0.03, 0.014))
    L.add("UpperTorso", tube(L.tier + "CapeTop", [pos(i / 20, 0.0, 0.02) for i in range(21)], 0.055, outer, sides=8))
    if hem is not None or hem_glow:
        pts = [Vector(pos(i / (nu * 2), 1.0, 0.015)) + Vector((0, 0, 0.01)) for i in range(nu * 2 + 1)]
        o = tube(L.tier + "CapeHem", pts, hem_r, L.glowm if hem_glow else hem, sides=6)
        (L.lit if hem_glow else L.add)("UpperTorso", o)
    return out, pos


def cape_ties(L, mat, clasp, gem=True):
    """Cords from the cape over the shoulders to clasps on the chest."""
    for s in (-1, 1):
        x = s * 0.72
        L.add("UpperTorso", tube(L.uid("CapeCord"), catmull([(x, -0.58, 0.98), (x, -0.2, 1.07), (x, 0.3, 1.06), (x * 0.95, 0.58, 0.88)], 4), 0.035, mat, sides=6))
        L.add("UpperTorso", lathe_disc(L.uid("Clasp"), 0.1, 0.05, (x * 0.95, 0.57, 0.86), clasp))
        if gem:
            L.lit("UpperTorso", S.ellipsoid(L.uid("ClaspGem"), (0.045, 0.03, 0.045), (x * 0.95, 0.63, 0.86), L.glowm, power=1.3, segs=6, rings=4))


def scarf(L, mat, tails=True, edge=None, jag=False, long=1.0):
    """Neck roll with a knot at the back and two tails flowing behind (UpperTorso)."""
    L.add("UpperTorso", tube(L.tier + "ScarfRoll", ring_pts(0, -0.02, 1.0, 0.84, 0.68, power=3.0, n=40) , 0.11, mat, closed=True, sides=10))
    L.add("UpperTorso", rbox(L.tier + "ScarfKnot", (0.15, 0.1, 0.13), (0.36, -0.74, 0.98), mat, power=3))
    if not tails:
        return
    k = long
    t1 = [(0.33, -0.76, 0.96), (0.42, -0.98, 0.8 - 0.05 * k), (0.52, -1.18, 0.56 - 0.15 * k), (0.6, -1.36, 0.28 - 0.3 * k)]
    t2 = [(0.42, -0.76, 0.98), (0.68, -0.94, 0.88), (0.94, -1.14, 0.74 - 0.05 * k), (1.12, -1.36, 0.6 - 0.15 * k)]
    for i, (ctrl, w) in enumerate(((t1, 0.2), (t2, 0.17))):
        L.add("UpperTorso", ribbon(L.tier + "ScarfTail%d" % i, ctrl, (1, 0.25 * (i * 2 - 1), 0), w, 0.035, mat,
                                   taper=(lambda t: 1 - 0.55 * t * t) if jag else None))


def fur_collar(L, mat, n=30):
    rnd = random.Random(5)
    for i in range(n):
        a = math.tau * i / n
        c, s = math.cos(a), math.sin(a)
        base = (0.8 * c, -0.02 + 0.64 * s, 1.0 + rnd.uniform(-0.03, 0.03))
        d = (c * 0.9, s * 0.9, rnd.uniform(0.1, 0.5))
        o, _ = horn(L.uid("Fur"), base, d, rnd.uniform(0.16, 0.24), 0.1, mat, bend=(0, 0, -0.06), steps=3, sides=6)
        L.add("UpperTorso", o)


def lapel_piping(L, mat=None, width=0.026):
    """Thin lines along both edges of both lapels (glowing unless mat is given)."""
    inner, outer, lw = L.lapels
    for path, lift in ((outer, 0.035 + 0.08), (inner, 0.07)):
        for side in (-1, 1):
            o = strip(L.uid("Piping"), lateral(path, side * lw * 0.43, lift + 0.002), width, 0.012, mat or L.glowm, lift=0.0, bevel=0)
            (L.add if mat else L.lit)("UpperTorso", o)


def hood_seams(L, hood, mat=None, radius=0.032):
    for sx in (-0.36, 0.36):
        pts = []
        for i in range(30):
            y = 0.62 - i * 1.3 / 29
            p, n = hit(hood, (sx, y, 4), (0, 0, -1))
            if p and p.z > 2.22:
                pts.append(p + n * 0.008)
        o = tube(L.uid("HoodSeam"), pts, radius, mat or L.glowm, sides=8)
        (L.add if mat else L.lit)("Head", o)


def brim_front(L, z=2.1):
    return front(named(L, "Head", "Brim"), 0, z)


def hood_tails(L, mat, count=2, length=1.0, width=0.17, jag=False, knot=True):
    if knot:
        L.add("Head", rbox(L.tier + "TailKnot", (0.17, 0.12, 0.12), (0, -0.8, 2.1), mat, power=3))
    for i in range(count):
        s = (i - (count - 1) / 2)
        x0 = s * 0.12
        ctrl = [(x0, -0.8, 2.08), (x0 * 1.6, -1.02, 1.95 - 0.05 * abs(s)), (x0 * 2.4, -1.24, 1.72 - 0.25 * (length - 1) - 0.1 * abs(s)),
                (x0 * 3.2, -1.45, 1.42 - 0.6 * (length - 1) - 0.18 * abs(s))]
        L.add("Head", ribbon(L.uid("HoodTail"), ctrl, (1, 0, 0), width, 0.03, mat,
                             taper=(lambda t: 1 - 0.7 * t ** 1.5) if jag else None))


def halo(L, ring=None, z=2.82, r=0.56, tilt=0.38, y0=-0.12, glow_r=0.045, sparkles=4):
    pts = [(r * math.cos(a), y0 + r * math.sin(a) * math.cos(tilt), z - r * math.sin(a) * math.sin(tilt)) for a in [math.tau * k / 48 for k in range(48)]]
    L.lit("Head", tube(L.tier + "Halo", pts, glow_r, L.glowm, closed=True, sides=10))
    if ring is not None:
        for dr, tag in ((0.085, "Out"), (-0.085, "In")):
            rr = r + dr
            p2 = [(rr * math.cos(a), y0 + rr * math.sin(a) * math.cos(tilt), z - rr * math.sin(a) * math.sin(tilt)) for a in [math.tau * k / 48 for k in range(48)]]
            L.add("Head", tube(L.tier + "HaloRing" + tag, p2, 0.022, ring, closed=True, sides=6))
    for k in range(sparkles):
        a = math.tau * k / sparkles + math.pi / sparkles
        c = Vector((r * math.cos(a), y0 + r * math.sin(a) * math.cos(tilt), z - r * math.sin(a) * math.sin(tilt)))
        sparkle(L, "Head", c, 0.12)


def sparkle(L, region, c, size, mat=None):
    """Four-point 3D star (two crossed star plates)."""
    c = Vector(c)
    for k, n in enumerate((Vector((0, 1, 0)), Vector((1, 0, 0)))):
        o = decal(L.uid("Spark"), star_outline(size, 4, 0.28), c - n * 0.012, n, mat or L.glowm, thick=0.024, lift=0.0)
        (L.add if mat else L.lit)(region, o)


def shard(L, region, c, size, direction=(0, 0, 1), mat=None):
    """Floating crystal: a stretched octahedron pointing along direction."""
    o = S.ellipsoid(L.uid("Shard"), (size * 0.45, size * 0.45, size), (0, 0, 0), mat or L.glowm, power=1.0, segs=4, rings=4)
    q = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized())
    o.data.transform(Matrix.Translation(Vector(c)) @ q.to_matrix().to_4x4())
    for p in o.data.polygons:
        p.use_smooth = False
    (L.add if mat else L.lit)(region, o)
    return o


def wisp(L, region, base, up, length, radius, side=(1, 0, 0), waves=1.3, amp=0.12, seed=0):
    """Smoky flame tendril: an S-curving taper rising from base (glows)."""
    rnd = random.Random(seed)
    up, side = Vector(up).normalized(), Vector(side).normalized()
    ph = rnd.uniform(0, math.tau)
    pts, radii = [], []
    for i in range(15):
        t = i / 14
        pts.append(Vector(base) + up * length * t + side * math.sin(t * math.pi * waves * 2 + ph) * amp * t)
        radii.append(radius * (1 - t) ** 0.7 * (1 + 0.25 * math.sin(t * 9 + ph)) + 0.006)
    return L.lit(region, taper_tube(L.uid("Wisp"), pts, radii, L.glowm, sides=8))


def scatter_stars(L, region, target, rays, mat, rnd, size=(0.05, 0.085), keep=None, glow_every=0):
    n = 0
    for origin, direction in rays:
        p, nrm = hit(target, origin, direction)
        if p is None or (keep and not keep(p, nrm)):
            continue
        n += 1
        is_glow = glow_every and n % glow_every == 0
        o = decal(L.uid("Star"), star_outline(rnd.uniform(*size), rnd.choice((4, 4, 5)), 0.42, rot=rnd.uniform(-0.3, 0.3)), p, nrm,
                  L.glowm if is_glow else mat, thick=0.012)
        (L.lit if is_glow else L.add)(region, o)


# ------------------------------------------------ armour
def dome_pauldron(L, plate, rim, under=None, gem=True, tilt=0.12, rim_glow=False, top=1.27, bottom=0.66, hx=0.53, hy=0.59, cx=1.47):
    """Rounded shoulder dome over the upper arm, a trim rim, a lame under it and a gem."""
    objs = []
    sh = shell(L.tier + "Pauld", plate, bottom, top, hx, hy, cx, power=3.2)
    objs.append((L.add, sh))
    rim_o = tube(L.tier + "PauldRim", ring_pts(cx, 0, bottom + 0.01, hx + 0.012, hy + 0.012, power=3.2, n=48), 0.035, L.glowm if rim_glow else rim, closed=True, sides=8)
    objs.append((L.lit if rim_glow else L.add, rim_o))
    if under is not None:
        objs.append((L.add, rbox(L.tier + "PauldLame", (hx - 0.03, hy - 0.02, 0.07), (cx + 0.03, 0, bottom - 0.08), under, power=10)))
        objs.append((L.add, rbox(L.tier + "PauldLameRim", (hx - 0.025, hy - 0.015, 0.018), (cx + 0.03, 0, bottom - 0.14), rim, power=10)))
    M = about(tilt, "Y", (cx - hx * 0.5, 0, top))
    xform([o for _, o in objs], M)
    for fn, o in objs:
        fn("RightUpperArm", o)
    if gem:
        p, n = hit(sh, (cx + 3, 0, (top + bottom) / 2 + 0.05), (-1, 0, 0))
        if p is not None:
            L.add("RightUpperArm", decal(L.uid("PauldMount"), diamond(0.11, 0.13), p, n, rim, thick=0.025))
            L.lit("RightUpperArm", decal(L.uid("PauldGem"), diamond(0.065, 0.085), p + n * 0.025, n, L.glowm, thick=0.025))
    return sh


def sode(L, plates, lace, rivet=None, tilt=-0.26, x=1.52, z=1.0, step=0.18, hx=0.5, hy=0.58, flare=0.05, glow_lace=False):
    """Samurai shoulder guard: stacked plates flaring out, laced trim on every edge."""
    out = []
    for k, mat in enumerate(plates):
        cx, cz = x + k * flare, z - k * step
        pad = rbox(L.tier + "Sode%d" % k, (hx + k * 0.01, hy + k * 0.01, 0.085), (0, 0, 0), mat, power=10, segs=24, rings=10)
        rim = rbox(L.tier + "SodeLace%d" % k, (hx + k * 0.01 + 0.006, hy + k * 0.01 + 0.006, 0.02), (0, 0, -0.07), L.glowm if glow_lace else lace, power=10, segs=24, rings=4)
        for o in (pad, rim):
            o.rotation_euler = (0, tilt, 0)
            o.location = (cx, 0, cz)
            C.apply_transforms([o])
        L.add("RightUpperArm", pad)
        (L.lit if glow_lace else L.add)("RightUpperArm", rim)
        out.append(pad)
        if rivet is not None:
            for yy in (-0.3, 0.0, 0.3):
                p, n = hit(pad, (cx + 3, yy, cz + 0.02), (-1, 0, 0))
                if p is not None:
                    L.add("RightUpperArm", S.ellipsoid(L.uid("Rivet"), (0.03, 0.03, 0.03), p + n * 0.01, rivet, segs=8, rings=6))
    return out


def do_plate(L, plate, trim, lames=3, top=0.55, sigil=None, sigil_mat=None):
    """Samurai chest plate over the lower chest with laced lames down to the belt."""
    hz = (top - 0.02) / 2
    do = L.add("UpperTorso", rbox(L.tier + "Do", (1.075, 0.66, hz + 0.02), (0, 0, top - hz), plate, power=8, segs=48, rings=24))
    L.add("UpperTorso", rbox(L.tier + "DoTop", (1.08, 0.665, 0.03), (0, 0, top - 0.02), trim, power=8, segs=48, rings=6))
    for i in range(lames):
        z = -0.06 - i * 0.16
        L.add("UpperTorso", rbox(L.tier + "Lame%d" % i, (1.07 - i * 0.004, 0.645, 0.075), (0, 0, z), plate, power=12, segs=40, rings=8))
        L.add("UpperTorso", rbox(L.tier + "LameLace%d" % i, (1.075 - i * 0.004, 0.65, 0.018), (0, 0, z - 0.068), trim, power=12, segs=40, rings=4))
    if sigil:
        sigil(do)
    return do


def kusazuri(L, plate, lace, rows=2, back=True, sides=True):
    spots = [(-0.5, 0.64, 0.16), (0.5, 0.64, 0.16)]
    if back:
        spots += [(-0.5, -0.64, -0.16), (0.5, -0.64, -0.16)]
    for i, (x, y, rot) in enumerate(spots):
        for k in range(rows):
            for mat, dz, grow, tag in ((plate, 0.0, 0.0, "P"), (lace, -0.075, 0.006, "L")):
                p = rbox(L.uid("Kusa" + tag), (0.4 + grow, 0.06 + grow, 0.08 if tag == "P" else 0.018), (0, 0, 0), mat, power=10, segs=16, rings=8)
                p.rotation_euler = (rot, 0, 0)
                p.location = (x, y + math.copysign(0.035 * k, y), -0.8 - k * 0.17 + dz)
                C.apply_transforms([p])
                L.add("LowerTorso", p)
    if sides:
        for side in (-1, 1):
            for k in range(rows):
                for mat, dz, grow, tag in ((plate, 0.0, 0.0, "P"), (lace, -0.075, 0.006, "L")):
                    p = rbox(L.uid("KusaS" + tag), (0.065 + grow, 0.44 + grow, 0.08 if tag == "P" else 0.018), (0, 0, 0), mat, power=10, segs=16, rings=8)
                    p.rotation_euler = (0, -side * 0.16, 0)
                    p.location = (side * (1.1 + 0.035 * k), 0, -0.8 - k * 0.17 + dz)
                    C.apply_transforms([p])
                    L.add("LowerTorso", p)


def greave(L, plate, ribs=None, knee=None, rib_glow=False):
    x = 0.49
    sune = L.add("RightLowerLeg", rbox(L.tier + "Greave", (0.48, 0.52, 0.31), (x, 0.03, -2.2), plate, power=10))
    if ribs is not None or rib_glow:
        for k in (-1, 0, 1):
            pts = path_on(sune, [(-x + k * 0.15, -1.95), (-x + k * 0.15, -2.45)], 0.04)
            o = strip(L.uid("GreaveRib"), pts, 0.035, 0.018, L.glowm if rib_glow else ribs, lift=0.003, bevel=0 if rib_glow else 0.3)
            (L.lit if rib_glow else L.add)("RightLowerLeg", o)
    if knee is not None:
        L.add("RightLowerLeg", rbox(L.tier + "Knee", (0.28, 0.14, 0.15), (x, 0.5, -1.92), knee, power=4))
    return sune


def arm_parts(L):
    return named(L, "RightUpperArm", "UpperSkin"), named(L, "RightLowerArm", "Bracer")


def arm_wrap(L, mat, turns=3.0, width=0.08):
    """Flat bandage wound round the (boxy) bracer from wrist to elbow."""
    pitch = 0.19 * 3.0 / turns
    o = H.rect_band(L.uid("Wrap"), 0.437, 0.497, -0.7, turns, pitch, max(width, pitch * 0.88), 0.025, mat)
    o.data.transform(Matrix.Translation((1.43, 0, 0)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    C.recalc_normals(o)
    return o


def glow_band(L, region, half, center, power=12):
    """Thin neon slab slightly bigger than a part: reads as a glowing line around it."""
    return L.lit(region, rbox(L.uid("Band"), half, center, L.glowm, power=power, segs=32, rings=4))


def oni_mask(L, lacq, bone, trim):
    """Replace the cloth mask with a lacquered demon menpo: nose, snarl, fangs, ridges."""
    drop(L, "Head", "Mask")
    prof = ((0.98, 0.7, 0.66, 0.0), (1.06, 0.8, 0.77, 0.04), (1.22, 0.83, 0.84, 0.06), (1.38, 0.82, 0.83, 0.06), (1.5, 0.8, 0.79, 0.04), (1.57, 0.785, 0.75, 0.02))
    st = []
    for i in range(len(prof) - 1):
        a0, a1 = prof[i], prof[i + 1]
        for k in range(4):
            t = k / 4
            st.append(tuple(a0[j] + (a1[j] - a0[j]) * t for j in range(4)))
    st.append(prof[-1])
    m = S.lofted(L.tier + "Menpo", [(z, hx, hy, 0.0, cy) for z, hx, hy, cy in st], lacq, power=2.6, n=64)
    top = max(v.co.z for v in m.data.vertices)
    for v in m.data.vertices:
        if v.co.z > top - 1e-4 and v.co.y > 0:
            v.co.z -= 0.13 * min(1.0, abs(v.co.x) / 0.55) * min(1.0, v.co.y / 0.4)
    L.add("Head", m)
    p, n = front(m, 0, 1.4)
    L.add("Head", rbox(L.tier + "MenpoNose", (0.09, 0.08, 0.12), p + Vector((0, 0.03, -0.01)), lacq, power=3))
    path = path_on(m, [(-0.34, 1.26), (-0.18, 1.2), (0, 1.19), (0.18, 1.2), (0.34, 1.26)], 0.03)
    L.add("Head", strip(L.tier + "Snarl", path, 0.12, 0.014, L.ink, lift=0.004, bevel=0))
    for i in range(6):
        u = -0.26 + i * 0.104
        p, n = front(m, u, 1.25 - 0.05 * (1 - (u / 0.34) ** 2))
        if p:
            L.add("Head", fang(L.uid("Fang"), p + n * 0.016, n, 0.065, 0.05, bone))
        p2, n2 = front(m, u + 0.052, 1.15 - 0.03 * (1 - (u / 0.34) ** 2))
        if p2 and i < 5:
            L.add("Head", fang(L.uid("FangLo"), p2 + n2 * 0.016, n2, 0.05, 0.045, bone, down=(0, 0, 1)))
    for s in (-1, 1):
        p, n = front(m, s * 0.37, 1.29)
        if p:
            L.add("Head", fang(L.uid("Tusk"), p + n * 0.016, n, 0.17, 0.08, bone))
        L.add("Head", strip(L.uid("Cheek"), path_on(m, [(s * 0.22, 1.5), (s * 0.5, 1.38), (s * 0.58, 1.18)], 0.03), 0.05, 0.03, trim, lift=0.004, bevel=0.3))
    return m


# ------------------------------------------------ tiers
def purple():
    L = Tier("purple", (100, 48, 168), (110, 54, 182), (46, 20, 80), (92, 44, 160))
    lav = sheen("purpleLav", (214, 160, 255), lo=0.7, hi=1.2)
    plate = sheen("purplePlate", (74, 34, 130))
    sash = cloth("purpleSash", (52, 24, 92))
    scarf_m = cloth("purpleScarf", (150, 96, 222), streaks=0.06)
    hood = head(L, {"eyes": "gem", "gem_mat": L.glowm, "brow": L.ink, "brim": L.cloth, "seam": True})
    del hood
    p, n = brim_front(L)
    L.add("Head", decal(L.uid("Crest"), [(-0.26, 0.07), (0.26, 0.07), (0.3, 0.0), (0.26, -0.07), (-0.26, -0.07), (-0.3, 0.0)], p, n, lav, thick=0.035))
    L.lit("Head", decal(L.uid("CrestGem"), diamond(0.06, 0.075), p + n * 0.035, n, L.glowm, thick=0.025))
    jacket = torso(L, {"vneck": L.skin, "collar": sash, "stitch": lav})
    medallion(L, "UpperTorso", jacket, 0.5, 0.6, 0.16, lav, star_outline(0.12, 4, 0.32), rim=sash)
    scarf(L, scarf_m)
    hips(L, {"belt": "blue", "gold": lav, "sash": sash, "gem": L.glowm})
    arm(L, {"armored": True, "stitch": lav, "sash": sash, "pads": False})
    dome_pauldron(L, plate, lav, under=plate)
    leg(L, {"wraps": True, "x": lav, "sash": sash})
    return L


def red():
    L = Tier("red", (176, 34, 34), (188, 40, 38), (70, 12, 12), (64, 18, 18))
    gold = sheen("redGold", (255, 196, 70))
    lacq = sheen("redLacq", (204, 36, 32), lo=0.62, hi=1.3)
    black = sheen("redBlack", (44, 22, 22))
    sash = cloth("redSash", (64, 14, 14))
    head(L, {"eyes": "gem", "gem_mat": L.glowm, "brow": L.ink, "brim": black, "seam": False})
    p, n = brim_front(L)
    # kuwagata: gold crescent horns rising from a crest plate on the brow band
    L.add("Head", decal(L.uid("CrestPlate"), [(-0.2, -0.08), (0.2, -0.08), (0.14, 0.09), (-0.14, 0.09)], p, n, gold, thick=0.04))
    L.lit("Head", decal(L.uid("CrestGem"), star_outline(0.075, 4, 0.4), p + n * 0.04, n, L.glowm, thick=0.025))
    for s in (-1, 1):
        o, _ = horn(L.uid("Kuwa"), (s * 0.12, p.y + 0.02, p.z + 0.04), (s * 0.85, 0.15, 0.7), 0.55, 0.06, gold, bend=(s * -0.08, 0.05, 0.42), steps=14, sides=8)
        L.add("Head", o)
    jacket = torso(L, {"vneck": L.skin, "collar": sash, "stitch": gold})
    del jacket

    def mon(do):
        p, _ = front(do, 0, 0.3)
        L.add("UpperTorso", lathe_disc(L.uid("Mon"), 0.17, 0.04, (0, p.y - 0.01, p.z), black))
        L.lit("UpperTorso", tube(L.uid("MonRing"), [(math.cos(a) * 0.13, p.y + 0.035, p.z + math.sin(a) * 0.13) for a in [math.tau * k / 32 for k in range(32)]], 0.018, L.glowm, closed=True, sides=6))
        L.lit("UpperTorso", decal(L.uid("MonGem"), diamond(0.06, 0.09), Vector((0, p.y + 0.03, p.z)), Vector((0, 1, 0)), L.glowm, thick=0.02))
    do_plate(L, lacq, gold, sigil=mon)
    scarf(L, sash)
    hips(L, {"belt": "blue", "gold": gold, "sash": sash, "gem": L.glowm, "pouches": False, "bandolier": False, "tassels": False})
    kusazuri(L, lacq, gold)
    arm(L, {"armored": True, "stitch": gold, "sash": black, "pads": False, "bracer": lacq})
    sode(L, [lacq, lacq, lacq], gold, rivet=gold)
    L.add("RightUpperArm", shell(L.tier + "SodeCap", black, 0.98, 1.16, 0.42, 0.5, 1.45, power=3.5))
    leg(L, {})
    greave(L, lacq, ribs=gold, knee=black)
    L.add("RightFoot", rbox(L.tier + "Ankle", (0.5, 0.56, 0.05), (0.49, 0.03, -2.5), black, power=10))
    return L


def visor_mask(L, metal, trim):
    """Stealth respirator: the cloth mask becomes a smooth metal face plate with
    vents on the cheeks and a ridge down the nose."""
    drop(L, "Head", "Mask")
    prof = ((0.98, 0.7, 0.66, 0.0), (1.06, 0.79, 0.76, 0.03), (1.22, 0.815, 0.8, 0.05), (1.38, 0.805, 0.8, 0.05), (1.5, 0.79, 0.77, 0.03), (1.57, 0.78, 0.74, 0.02))
    st = []
    for i in range(len(prof) - 1):
        a0, a1 = prof[i], prof[i + 1]
        for k in range(4):
            t = k / 4
            st.append(tuple(a0[j] + (a1[j] - a0[j]) * t for j in range(4)))
    st.append(prof[-1])
    m = S.lofted(L.tier + "Visor", [(z, hx, hy, 0.0, cy) for z, hx, hy, cy in st], metal, power=2.6, n=64)
    top = max(v.co.z for v in m.data.vertices)
    for v in m.data.vertices:
        if v.co.z > top - 1e-4 and v.co.y > 0:
            v.co.z -= 0.13 * min(1.0, abs(v.co.x) / 0.55) * min(1.0, v.co.y / 0.4)
    L.add("Head", m)
    L.add("Head", strip(L.uid("Ridge"), path_on(m, [(0, 1.5), (0, 1.06)], 0.03), 0.06, 0.03, trim, lift=0.003, bevel=0.4))
    for s_ in (-1, 1):
        for k in range(3):
            z = 1.34 - k * 0.09
            L.add("Head", strip(L.uid("Vent"), path_on(m, [(s_ * 0.16, z), (s_ * 0.42, z - 0.04)], 0.03), 0.035, 0.022, trim, lift=0.003, bevel=0.3))
        L.lit("Head", strip(L.uid("VisorLine"), path_on(m, [(s_ * 0.08, 1.5), (s_ * 0.6, 1.44)], 0.03), 0.025, 0.014, L.glowm, lift=0.004, bevel=0))
    return m


def black():
    L = Tier("black", (36, 36, 42), (44, 44, 52), (14, 14, 16), (26, 26, 30), streaks=0.08)
    silver = sheen("blackSilver", (200, 205, 215))
    gun = sheen("blackGun", (62, 64, 74), lo=0.5, hi=1.6)
    sash = cloth("blackSash", (20, 20, 24))
    hood = head(L, {"eyes": "demon", "glow": L.glowm, "brow": L.ink, "brim": L.cloth, "seam": True})
    hood_seams(L, hood)
    visor_mask(L, gun, silver)
    p, n = brim_front(L)
    L.add("Head", decal(L.uid("Hitai"), [(-0.3, 0.075), (0.3, 0.075), (0.33, 0.0), (0.3, -0.075), (-0.3, -0.075), (-0.33, 0.0)], p, n, silver, thick=0.03))
    L.lit("Head", decal(L.uid("HitaiLine"), [(-0.22, 0.014), (0.22, 0.014), (0.22, -0.014), (-0.22, -0.014)], p + n * 0.03, n, L.glowm, thick=0.012))
    hood_tails(L, sash, count=2, length=1.25, width=0.13)
    jacket = torso(L, {"vneck": L.skin, "collar": sash})
    lapel_piping(L, mat=silver, width=0.024)
    for s_ in (-1, 1):
        seam(L, "UpperTorso", jacket, (s_ * 0.95, 3, 0.95), (0, -1, 0), (0, 0, -1), 1.5)
    # harness crossing the lapel, carrying three shuriken
    hp = path_on(jacket, [(-0.62, 0.98), (0.1, 0.2), (0.7, -0.5)], 0.05)
    L.add("UpperTorso", strip(L.uid("Harness"), lateral(hp, 0, 0.125), 0.13, 0.035, gun, lift=0.0, bevel=0.4))
    for i, t in enumerate((0.3, 0.48, 0.66)):
        q, m = hp[int(t * (len(hp) - 1))]
        q = q + m * 0.165
        L.add("UpperTorso", decal(L.uid("Shuriken"), star_outline(0.085, 4, 0.3, rot=0.3), q, m, silver, thick=0.022))
        L.lit("UpperTorso", S.ellipsoid(L.uid("ShurikenCore"), (0.022, 0.022, 0.022), q + m * 0.03, L.glowm, segs=8, rings=6))
    scarf(L, sash, long=1.4)
    hips(L, {"belt": "blue", "gold": silver, "sash": sash, "gem": L.glowm, "pouches": False, "bandolier": False})
    glow_band(L, "LowerTorso", (1.09, 0.6, 0.012), (0, 0, -0.66))
    arm(L, {"armored": True, "sash": gun, "pads": False, "bracer": sash})
    up, br = arm_parts(L)
    for k, (z, hz) in enumerate(((1.02, 0.075), (0.84, 0.06), (0.7, 0.05))):
        hx, hy = 0.5 - k * 0.025, 0.57 - k * 0.025
        plate = rbox(L.uid("Plate"), (hx, hy, hz), (0, 0, 0), gun, power=8)
        edge = rbox(L.uid("PlateEdge"), (hx + 0.006, hy + 0.006, 0.014), (0, 0, -hz + 0.022), silver, power=8, segs=32, rings=4)
        for o in (plate, edge):
            o.rotation_euler = (0, 0.22, 0)
            o.location = (1.5 + k * 0.03, 0, z)
            C.apply_transforms([o])
        L.add("RightUpperArm", plate)
        L.add("RightUpperArm", edge)
    glow_band(L, "RightUpperArm", (0.43, 0.5, 0.012), (1.53, 0, 0.92), power=8)
    for i in range(2):
        drop(L, "RightLowerArm", "Strap%d" % i)
    L.add("RightLowerArm", rbox(L.uid("Vambrace"), (0.45, 0.51, 0.22), (1.43, 0, -0.4), gun, power=10))
    for z in (-0.18, -0.62):
        L.add("RightLowerArm", rbox(L.uid("VambEdge"), (0.457, 0.517, 0.022), (1.43, 0, z), silver, power=10, segs=32, rings=4))
    seam(L, "RightLowerArm", br, (1.43 + 3, 0, -0.2), (-1, 0, 0), (0, 0, -1), 0.4)
    leg(L, {"wraps": True, "x": silver, "sash": gun})
    th = named(L, "RightUpperLeg", "Thigh")
    seam(L, "RightUpperLeg", th, (0.49 + 3, 0, -1.0), (-1, 0, 0), (0, 0, -1), 0.95)
    # thigh holster with two kunai rings
    L.add("RightUpperLeg", rbox(L.uid("Holster"), (0.49, 0.53, 0.045), (0.49, 0, -1.3), sash, power=12))
    L.add("RightUpperLeg", rbox(L.uid("Pouch"), (0.08, 0.2, 0.17), (0.98, 0.05, -1.38), gun, power=6))
    for dy in (-0.07, 0.07):
        ring = [(1.06, 0.05 + dy + math.cos(a) * 0.05, -1.12 + math.sin(a) * 0.05) for a in [math.tau * k / 16 for k in range(16)]]
        L.add("RightUpperLeg", tube(L.uid("KunaiRing"), ring, 0.012, silver, closed=True, sides=6))
        L.add("RightUpperLeg", rbox(L.uid("KunaiGrip"), (0.025, 0.025, 0.06), (1.06, 0.05 + dy, -1.22), sash, power=4))
    glow_band(L, "RightFoot", (0.49, 0.57, 0.012), (0.49, 0.05, -2.86), power=5)
    return L


def white():
    L = Tier("white", (232, 238, 246), (204, 222, 244), (170, 190, 215), (196, 210, 228), noise=0.05, streaks=0.05)
    ice = cloth("whiteIce", (110, 196, 245), streaks=0.04)
    silver = sheen("whiteSilver", (150, 192, 236), lo=0.6, hi=1.3)
    deep = sheen("whiteDeep", (58, 110, 182))
    icem = sheen("whiteCrystal", (176, 226, 255), lo=0.65, hi=1.35, roblox="Glass")
    brim = cloth("whiteBrim", (176, 206, 238), streaks=0.04)
    sash = cloth("whiteSash", (150, 176, 212))
    fur = H.paint("whiteFur", (248, 250, 255), noise=0.12, scale=40, streaks=0.25, roblox="Fabric")
    brow = H.paint("whiteBrow", (60, 104, 160), roughness=0.5)
    hood = head(L, {"eyes": "gem", "gem_mat": L.glowm, "brow": brow, "brim": brim, "seam": True})
    hood_seams(L, hood)
    p, n = brim_front(L)
    L.add("Head", decal(L.uid("MoonPlate"), crescent_outline(0.15, rot=1.1), p, n, silver, thick=0.035))
    L.lit("Head", decal(L.uid("MoonGlow"), crescent_outline(0.1, rot=1.1), p + n * 0.035, n, L.glowm, thick=0.02))
    # frost crystals crowning the hood
    for i, (x, y, dx, dz, ln) in enumerate(((0.0, -0.1, 0, 1, 0.36), (0.22, -0.18, 0.45, 1, 0.26), (-0.22, -0.18, -0.45, 1, 0.26), (0.38, -0.3, 0.8, 0.8, 0.18), (-0.38, -0.3, -0.8, 0.8, 0.18))):
        hp, hn = hit(hood, (x, y, 4), (0, 0, -1))
        if hp is not None:
            d = Vector((dx, -0.15, dz)).normalized()
            shard(L, "Head", hp + d * ln * 0.5, ln * 0.6, d, mat=icem)
            shard(L, "Head", hp + d * ln * 0.8, ln * 0.28, d)
    jacket = torso(L, {"vneck": L.skin, "collar": sash, "stitch": ice})
    lapel_piping(L)
    p = medallion(L, "UpperTorso", jacket, 0.5, 0.6, 0.16, deep, crescent_outline(0.11, rot=1.1), rim=silver)
    fur_collar(L, fur)
    cape(L, sash, L.cloth, None, jag=0.16, teeth=9, rag=0.25, hem_glow=True, flare=0.3, seed=3)
    cape_ties(L, silver, silver)
    out = named(L, "UpperTorso", "Cape")
    q, m = front(out, 0, -0.1, back=True)
    L.add("UpperTorso", decal(L.uid("BackMoon"), crescent_outline(0.34, rot=1.1), q, m, silver, thick=0.03))
    L.lit("UpperTorso", decal(L.uid("BackMoonGlow"), crescent_outline(0.24, rot=1.1), q + m * 0.03, m, L.glowm, thick=0.02))
    hips(L, {"belt": "blue", "gold": silver, "sash": sash, "gem": L.glowm})
    arm(L, {"armored": True, "stitch": ice, "sash": sash, "pads": False})
    sh = dome_pauldron(L, silver, ice, under=L.cloth, gem=False)
    for i, (dy, ln, lean) in enumerate(((0.0, 0.42, 0.25), (0.26, 0.3, 0.45), (-0.26, 0.3, 0.45), (0.12, 0.22, 0.85), (-0.14, 0.22, 0.85))):
        hp, hn = hit(sh, (1.6 + lean * 0.3, dy, 4), (0, 0, -1))
        if hp is not None:
            d = Vector((lean, dy * 0.6, 1)).normalized()
            shard(L, "RightUpperArm", hp + d * ln * 0.45, ln * 0.55, d, mat=icem)
            shard(L, "RightUpperArm", hp + d * ln * 0.78, ln * 0.26, d)
    glow_band(L, "RightLowerArm", (0.44, 0.5, 0.012), (1.43, 0, -0.71))
    leg(L, {"wraps": True, "x": ice, "sash": sash})
    return L


def gold():
    L = Tier("gold", (186, 128, 26), (240, 226, 178), (108, 72, 16), (112, 74, 16))
    au = sheen("goldAu", (240, 180, 44), lo=0.42, hi=1.55)
    cream = sheen("goldCream", (255, 248, 218), lo=0.75, hi=1.12, roblox="Fabric")
    dk = sheen("goldDark", (128, 88, 20))
    capem = cloth("goldCape", (250, 244, 222), noise=0.05, streaks=0.05)
    hood = head(L, {"eyes": "gem", "gem_mat": L.glowm, "brow": L.ink, "brim": cream, "seam": True})
    hood_seams(L, hood, mat=au, radius=0.034)
    p, n = brim_front(L)
    # sun crest: rays fanning up from a gold disc with a glowing heart
    for k in range(9):
        a = math.radians(10 + k * 20)
        ln = 0.36 if k % 2 == 0 else 0.24
        o, _ = horn(L.uid("Ray"), (p.x, p.y + 0.02, p.z + 0.02), (math.cos(a), 0.12, math.sin(a)), ln, 0.035, au, steps=4, sides=6)
        L.add("Head", o)
    L.add("Head", lathe_disc(L.uid("Sun"), 0.13, 0.05, (p.x, p.y, p.z + 0.02), au))
    L.lit("Head", decal(L.uid("SunGem"), star_outline(0.085, 8, 0.6), Vector((p.x, p.y + 0.05, p.z + 0.02)), Vector((0, 1, 0)), L.glowm, thick=0.025))
    jacket = torso(L, {"vneck": L.skin, "collar": dk, "stitch": au})
    del jacket

    def sunburst(do):
        p, _ = front(do, 0, 0.3)
        for k in range(12):
            a = math.tau * k / 12
            ln = 0.4 if k % 2 == 0 else 0.26
            pts = path_on(do, [(0.11 * math.cos(a), 0.3 + 0.11 * math.sin(a)), ((0.11 + ln) * math.cos(a), 0.3 + (0.11 + ln) * math.sin(a) * 0.5)], 0.03)
            if len(pts) > 2:
                L.add("UpperTorso", strip(L.uid("Burst"), pts, 0.05, 0.018, cream, lift=0.003, bevel=0, taper=lambda t: 1 - 0.85 * t))
        L.add("UpperTorso", lathe_disc(L.uid("Boss"), 0.13, 0.06, (0, p.y - 0.01, p.z), au))
        L.lit("UpperTorso", S.ellipsoid(L.uid("BossGem"), (0.08, 0.05, 0.08), (0, p.y + 0.06, p.z), L.glowm, power=1.4, segs=8, rings=6))
    do_plate(L, au, cream, lames=3, sigil=sunburst)
    lapel_piping(L)
    cape(L, capem, dk, au, flare=0.36, seed=2, hem_r=0.04)
    cape_ties(L, au, au)
    out = named(L, "UpperTorso", "Cape")
    q, m = front(out, 0, -0.1, back=True)
    L.add("UpperTorso", decal(L.uid("BackSun"), star_outline(0.36, 12, 0.66), q, m, au, thick=0.03))
    L.lit("UpperTorso", decal(L.uid("BackSunGem"), star_outline(0.15, 8, 0.6), q + m * 0.03, m, L.glowm, thick=0.02))
    scarf(L, cream, tails=False)
    hips(L, {"belt": "blue", "gold": au, "sash": dk, "gem": L.glowm, "bandolier": False})
    kusazuri(L, au, cream, back=False)
    arm(L, {"armored": True, "stitch": cream, "sash": cream, "pads": False, "bracer": au})
    sleeve = cloth("goldSleeve", (96, 60, 14))
    for o in arm_parts(L)[:1] + (named(L, "RightLowerArm", "ForeSkin"),):
        o.data.materials[0] = sleeve
    sode(L, [au, au, au], cream, rivet=cream, z=1.02, step=0.17)
    sh = L.add("RightUpperArm", shell(L.tier + "Cap", au, 0.98, 1.2, 0.44, 0.52, 1.47, power=3.5))
    hp, hn = hit(sh, (1.47 + 3, 0, 1.06), (-1, 0, 0))
    L.lit("RightUpperArm", S.ellipsoid(L.uid("CapGem"), (0.03, 0.07, 0.07), hp + hn * 0.02, L.glowm, power=1.4, segs=8, rings=6))
    leg(L, {})
    greave(L, au, ribs=cream, knee=au)
    L.add("RightFoot", rbox(L.tier + "Ankle", (0.5, 0.56, 0.05), (0.49, 0.03, -2.5), cream, power=10))
    return L


def crimson():
    L = Tier("crimson", (134, 12, 34), (148, 16, 40), (34, 6, 12), (40, 8, 14))
    accent = cloth("crimsonAccent", (255, 70, 100), streaks=0.04)
    lacq = sheen("crimsonLacq", (62, 10, 18))
    bone = H.paint("crimsonBone", (236, 222, 200), noise=0.05, roughness=0.35)
    hornm = H.paint("crimsonHorn", (40, 22, 26), noise=0.12, scale=40, streaks=0.2, roughness=0.35)
    sash = cloth("crimsonSash", (24, 4, 8))
    head(L, {"eyes": "demon", "glow": L.glowm, "brow": L.ink, "brim": lacq, "seam": False})
    m = oni_mask(L, lacq, bone, accent)
    for s in (-1, 1):
        L.lit("Head", strip(L.uid("MaskMark"), path_on(m, [(s * 0.12, 1.5), (s * 0.18, 1.4), (s * 0.12, 1.33)], 0.02), 0.03, 0.014, L.glowm, lift=0.004, bevel=0))
        body, tip = horn(L.uid("Horn"), (s * 0.4, 0.12, 2.3), (s * 0.62, 0.12, 1), 0.8, 0.14, hornm, tip_mat=L.glowm, tip=0.28, bend=(s * -0.18, 0.18, 0.28), ridges=0.08, steps=14)
        L.add("Head", body)
        L.lit("Head", tip)
    p, n = brim_front(L)
    L.lit("Head", decal(L.uid("BrowGem"), diamond(0.05, 0.09), p, n, L.glowm, thick=0.03))
    jacket = torso(L, {"vneck": L.skin, "collar": sash, "stitch": accent})
    lapel_piping(L)
    for k in range(3):
        pts = path_on(jacket, [(-0.3 - k * 0.15, 0.7), (-0.5 - k * 0.15, 0.06)], 0.03)
        L.lit("UpperTorso", strip(L.uid("Scar"), pts, 0.06, 0.02, L.glowm, lift=0.004, bevel=0, taper=lambda t: 0.3 + 0.7 * math.sin(t * math.pi)))
    scarf(L, sash, jag=True)
    cape(L, sash, L.cloth, None, jag=0.32, teeth=6, rag=0.4, hem_glow=True, flare=0.34, seed=7, hem_r=0.028)
    hips(L, {"belt": "blue", "gold": bone, "sash": sash, "gem": L.glowm, "pouches": False, "bandolier": False, "tassels": False})
    for i, (x, w, ln) in enumerate(((-0.55, 0.3, 0.5), (0.0, 0.26, 0.42), (0.55, 0.3, 0.5))):
        L.add("LowerTorso", jag_tail(L.uid("Rag"), (x, 0.62, -0.72), w, ln, L.cloth if i != 1 else sash, points=2, tilt=0.1, seed=i + 3))
    arm(L, {"armored": True, "stitch": accent, "sash": sash, "pads": False, "bracer": lacq})
    plates = sode(L, [lacq, lacq], accent, rivet=bone, z=1.0, step=0.19)
    for i in range(3):
        o, _ = horn(L.uid("Spike"), (1.48 + i * 0.05, -0.28 + 0.28 * i, 1.08), (0.35, 0, 1), 0.34 - 0.05 * abs(i - 1), 0.075, bone, steps=4, sides=8)
        L.add("RightUpperArm", o)
    del plates
    glow_band(L, "RightLowerArm", (0.44, 0.5, 0.012), (1.43, 0, -0.71))
    leg(L, {"wraps": True, "x": accent, "sash": sash})
    th = named(L, "RightUpperLeg", "Thigh")
    seam(L, "RightUpperLeg", th, (0.49 + 3, 0, -1.0), (-1, 0, 0), (0, 0, -1), 0.95)
    return L


def shadow():
    L = Tier("shadow", (30, 24, 46), (36, 28, 54), (10, 8, 16), (22, 18, 34))
    accent = cloth("shadowAccent", (140, 70, 255), streaks=0.04)
    plate = sheen("shadowPlate", (44, 34, 66))
    sash = cloth("shadowSash", (14, 10, 22))
    rag = cloth("shadowRag", (24, 18, 38), streaks=0.2)
    hood = head(L, {"eyes": "demon", "glow": L.glowm, "brow": L.ink, "brim": L.cloth, "seam": False})
    hood_tails(L, rag, count=3, length=1.5, width=0.19, jag=True)
    # wisps curling off the hood
    for s in (-1, 1):
        hp, hn = hit(hood, (s * 0.4, -0.4, 4), (0, 0, -1))
        wisp(L, "Head", hp - hn * 0.03, (s * 0.35, -0.6, 1), 0.75, 0.1, side=(s, 0, 0), seed=s + 2)
    # torn veil under the mask
    for i, (x, w) in enumerate(((-0.42, 0.26), (0.0, 0.3), (0.42, 0.26))):
        L.add("Head", jag_tail(L.uid("Veil"), (x, 0.7 - abs(x) * 0.15, 1.04), w, 0.3, rag, points=2, thick=0.025, tilt=0.12, seed=i + 11))
    jacket = torso(L, {"vneck": L.skin, "collar": sash, "stitch": accent})
    lapel_piping(L)
    p = medallion(L, "UpperTorso", jacket, 0.5, 0.6, 0.15, plate, diamond(0.07, 0.11), rim=accent)
    scarf(L, rag, jag=True, long=1.5)
    cape(L, rag, sash, None, jag=0.5, teeth=7, rag=0.6, hem_glow=True, flare=0.42, seed=11, hem_r=0.024)
    # wisps rising behind the shoulders and orbiting shadow orbs
    for s in (-1, 1):
        wisp(L, "UpperTorso", (s * 0.6, -0.66, 0.92), (s * 0.3, -0.6, 1), 1.05, 0.13, side=(s, 0, 0), amp=0.16, seed=s + 5)
        wisp(L, "UpperTorso", (s * 0.25, -0.7, 0.95), (s * 0.1, -0.7, 1), 0.8, 0.09, side=(s, 0, 0), amp=0.12, seed=s + 9)
    for c, r in (((1.25, -0.85, 1.45), 0.09), ((-1.3, -0.8, 1.2), 0.08), ((0.15, -1.15, 1.8), 0.07)):
        L.lit("UpperTorso", S.ellipsoid(L.uid("Orb"), (r, r, r), c, L.glowm, segs=12, rings=8))
        L.add("UpperTorso", tube(L.uid("OrbRing"), [(c[0] + math.cos(a) * r * 1.7, c[1] + math.sin(a) * r * 1.7 * 0.5, c[2] + math.sin(a) * r * 1.7 * 0.8) for a in [math.tau * k / 24 for k in range(24)]], 0.014, plate, closed=True, sides=6))
    hips(L, {"belt": "blue", "gold": accent, "sash": sash, "gem": L.glowm, "pouches": False, "bandolier": False})
    for i, (x, y, w, ln) in enumerate(((-0.6, 0.6, 0.3, 0.6), (0.5, 0.61, 0.26, 0.5), (-0.1, -0.61, 0.36, 0.62), (0.6, -0.6, 0.28, 0.52))):
        L.add("LowerTorso", jag_tail(L.uid("Tatter"), (x, y, -0.7), w, ln, rag if i % 2 else sash, points=3, tilt=0.12 if y > 0 else -0.12, seed=i + 21))
    arm(L, {"armored": True, "stitch": accent, "sash": sash, "pads": False, "bracer": L.cloth})
    sh = dome_pauldron(L, plate, accent, under=None, gem=True, rim_glow=True)
    for i, (dy, w) in enumerate(((-0.32, 0.22), (0.0, 0.26), (0.32, 0.22))):
        L.add("RightUpperArm", jag_tail(L.uid("ArmRag"), (1.98, dy, 0.74), w, 0.38, rag, points=2, thick=0.025, yaw=math.pi / 2, seed=i + 31))
    wisp(L, "RightUpperArm", (1.62, -0.2, 1.12), (0.45, -0.4, 1), 0.6, 0.09, side=(0, 1, 0), seed=13)
    del sh
    L.add("RightLowerArm", arm_wrap(L, rag, turns=2.6, width=0.09))
    L.add("RightLowerArm", jag_tail(L.uid("WrapEnd"), (1.43, -0.5, -0.2), 0.12, 0.45, rag, points=1, thick=0.02, tilt=-0.5, seed=41))
    leg(L, {"wraps": True, "x": accent, "sash": sash})
    L.add("RightLowerLeg", jag_tail(L.uid("ShinRag"), (0.49 + 0.5, 0.0, -1.98), 0.3, 0.36, rag, points=2, thick=0.02, yaw=math.pi / 2, seed=51))
    th = named(L, "RightUpperLeg", "Thigh")
    seam(L, "RightUpperLeg", th, (0.49 + 3, 0, -1.0), (-1, 0, 0), (0, 0, -1), 0.95)
    return L


def celestial():
    L = Tier("celestial", (30, 44, 112), (234, 230, 212), (18, 24, 64), (24, 34, 92))
    gold = sheen("celestialGold", (255, 214, 110), lo=0.6, hi=1.4)
    cream = sheen("celestialCream", (240, 236, 220), lo=0.72, hi=1.15)
    sash = cloth("celestialSash", (20, 28, 74))
    rnd = random.Random(42)
    hood = head(L, {"eyes": "gem", "gem_mat": L.glowm, "brow": L.ink, "brim": cream, "seam": False})
    halo(L, ring=gold)
    p, n = brim_front(L)
    L.add("Head", decal(L.uid("Circlet"), star_outline(0.13, 4, 0.36), p, n, gold, thick=0.035))
    L.lit("Head", decal(L.uid("CircletGem"), star_outline(0.075, 4, 0.36), p + n * 0.035, n, L.glowm, thick=0.025))
    rays = []
    for k in range(70):
        a = rnd.uniform(0, math.tau)
        el = rnd.uniform(-0.4, 1.3)
        d = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
        rays.append((Vector((0, 0, 1.73)) + d * 3, -d))
    scatter_stars(L, "Head", hood, rays, gold, rnd, keep=lambda q, m: not (q.y > 0.15 and q.z < 2.3) and not (1.94 < q.z < 2.26), glow_every=4)
    jacket = torso(L, {"vneck": L.skin, "collar": sash, "stitch": gold})
    medallion(L, "UpperTorso", jacket, 0.5, 0.6, 0.16, gold, star_outline(0.12, 5, 0.42), rim=cream)
    rays = [((rnd.uniform(-0.95, 0.95), -3, rnd.uniform(-0.6, 0.95)), (0, 1, 0)) for _ in range(14)]
    rays += [((rnd.uniform(-0.95, 0.95), 3, rnd.uniform(-0.55, 0.0)), (0, -1, 0)) for _ in range(8)]
    scatter_stars(L, "UpperTorso", jacket, rays, gold, rnd, glow_every=3)
    lapel_piping(L, mat=gold, width=0.022)
    scarf(L, cream, tails=False)
    out, pos = cape(L, L.cloth, cream, gold, flare=0.36, seed=5, hem_r=0.035)
    cape_ties(L, gold, gold)
    # constellations on the cape: stars joined by fine gold lines
    pts = []
    for k in range(18):
        q, m = front(out, rnd.uniform(-0.85, 0.85), rnd.uniform(-1.55, 0.75), back=True)
        if q is not None:
            pts.append((q, m))
    for i, (q, m) in enumerate(pts):
        big = i % 3 == 0
        o = decal(L.uid("CapeStar"), star_outline(0.09 if big else 0.06, 4 if i % 2 else 5, 0.4, rot=rnd.uniform(-0.3, 0.3)), q, m, L.glowm if big else gold, thick=0.014)
        (L.lit if big else L.add)("UpperTorso", o)
    for a, b in ((0, 3), (3, 6), (6, 9), (1, 4), (4, 7), (7, 10), (2, 5), (5, 8)):
        if b < len(pts):
            (qa, _), (qb, _) = pts[a], pts[b]
            line = path_on(out, [(-qa.x, qa.z), (-qb.x, qb.z)], 0.04, back=True)
            if len(line) > 2:
                L.add("UpperTorso", strip(L.uid("Line"), line, 0.014, 0.008, gold, lift=0.003, bevel=0))
    for c, s_ in (((1.3, -0.8, 1.5), 0.15), ((-1.32, -0.75, 1.25), 0.13), ((0.0, -1.1, 1.95), 0.12)):
        sparkle(L, "UpperTorso", c, s_)
        L.add("UpperTorso", tube(L.uid("Orbit"), [(c[0] + math.cos(a) * s_ * 1.2, c[1] + math.sin(a) * s_ * 0.6, c[2] + math.sin(a) * s_ * 0.9) for a in [math.tau * k / 24 for k in range(24)]], 0.012, gold, closed=True, sides=6))
    skirt = hips(L, {"belt": "blue", "gold": gold, "sash": sash, "gem": L.glowm})
    rays = [((rnd.uniform(-1.0, 1.0), 3, rnd.uniform(-1.0, -0.8)), (0, -1, 0)) for _ in range(6)]
    scatter_stars(L, "LowerTorso", skirt, rays, gold, rnd, size=(0.04, 0.06))
    arm(L, {"armored": True, "stitch": gold, "sash": sash, "pads": False, "bracer": cream})
    dome_pauldron(L, cream, gold, under=L.cloth, gem=True)
    leg(L, {})
    th = named(L, "RightUpperLeg", "Thigh")
    rays = [((0.49 + rnd.uniform(-0.4, 0.4), 3, rnd.uniform(-1.9, -1.05)), (0, -1, 0)) for _ in range(4)]
    rays += [((3, rnd.uniform(-0.4, 0.4), rnd.uniform(-1.9, -1.05)), (-1, 0, 0)) for _ in range(3)]
    scatter_stars(L, "RightUpperLeg", th, rays, gold, rnd, size=(0.04, 0.065), glow_every=3)
    greave(L, cream, ribs=gold, knee=gold)
    return L


def void():
    L = Tier("void", (18, 10, 34), (26, 14, 46), (6, 2, 12), (14, 8, 26))
    accent = cloth("voidAccent", (230, 70, 255), streaks=0.04)
    plum = sheen("voidPlum", (58, 14, 96))
    obsid = sheen("voidObsidian", (24, 14, 36), lo=0.5, hi=1.8)
    sash = cloth("voidSash", (40, 0, 70))
    rnd = random.Random(7)
    hood = head(L, {"eyes": "demon", "glow": L.glowm, "brow": L.ink, "brim": plum, "seam": False})
    mask = named(L, "Head", "Mask")
    for s in (-1, 1):
        body, tip = horn(L.uid("Horn"), (s * 0.42, 0.06, 2.22), (s * 0.5, -0.12, 1), 0.95, 0.15, obsid, tip_mat=L.glowm, tip=0.3, bend=(s * 0.32, -0.3, 0.2), ridges=0.06, steps=16)
        L.add("Head", body)
        L.lit("Head", tip)
    # eclipse halo: a dark ring behind the head with a neon rim and a corona of shards
    c = Vector((0, -0.8, 2.0))
    R = 0.88
    L.add("Head", C.lathe(L.uid("Eclipse"), [(R - 0.07, 0.0), (R + 0.11, 0.0), (R + 0.11, 0.05), (R - 0.07, 0.05)], 48, obsid, axis="Y"))
    L.parts["Head"][-1].data.transform(Matrix.Translation(c - Vector((0, 0.025, 0))))
    for dy in (0.03, -0.03):
        L.lit("Head", tube(L.uid("EclipseRim"), [(c.x + math.cos(a) * (R - 0.06), c.y + dy, c.z + math.sin(a) * (R - 0.06)) for a in [math.tau * k / 64 for k in range(64)]], 0.035, L.glowm, closed=True, sides=8))
    L.lit("Head", tube(L.uid("EclipseCore"), [(c.x + math.cos(a) * 0.3, c.y - 0.03, c.z + math.sin(a) * 0.3) for a in [math.tau * k / 40 for k in range(40)]], 0.03, L.glowm, closed=True, sides=8))
    for k in range(12):
        a = math.tau * k / 12 + 0.13
        ln = 0.42 if k % 2 == 0 else 0.26
        base = c + Vector((math.cos(a), 0, math.sin(a))) * (R + 0.05)
        body, tip = horn(L.uid("Corona"), base, (math.cos(a), 0, math.sin(a)), ln, 0.06, obsid, tip_mat=L.glowm, tip=0.35, steps=4, sides=6)
        L.add("Head", body)
        L.lit("Head", tip)
    for k in range(9):
        a = rnd.uniform(0, math.tau)
        el = rnd.uniform(0.0, 1.2)
        d = Vector((math.cos(a) * math.cos(el), -abs(math.sin(a)) * math.cos(el), math.sin(el)))
        crack(L, "Head", hood, Vector((0, 0, 1.73)) + d * 3, -d, rnd, length=0.55, width=0.035, branches=1)
    for s in (-1, 1):
        crack(L, "Head", mask, (s * 0.45, 3, 1.3), (0, -1, 0), rnd, length=0.35, width=0.03, branches=1, heading=(s * 0.4, 0, -1))
    jacket = torso(L, {"vneck": L.skin, "collar": sash, "stitch": accent})
    lapel_piping(L)
    p, _ = front(jacket, 0.5, 0.6)
    L.add("UpperTorso", lathe_disc(L.uid("VoidEye"), 0.17, 0.05, (p.x, p.y - 0.012, p.z), obsid))
    L.lit("UpperTorso", decal(L.uid("VoidPupil"), diamond(0.05, 0.1), Vector((p.x, p.y + 0.04, p.z)), Vector((0, 1, 0)), L.glowm, thick=0.02))
    L.lit("UpperTorso", tube(L.uid("VoidEyeRim"), [(p.x + math.cos(a) * 0.15, p.y + 0.04, p.z + math.sin(a) * 0.15) for a in [math.tau * k / 32 for k in range(32)]], 0.02, L.glowm, closed=True, sides=6))
    for vx, z, hd in ((-0.55, 0.75, (0.3, 0, -1)), (-0.75, 0.1, (-0.4, 0, -1)), (0.62, -0.05, (0.2, 0, -1)), (0.3, 0.35, (1, 0, -0.3))):
        crack(L, "UpperTorso", jacket, (-vx, 3, z), (0, -1, 0), rnd, length=0.6, branches=2, heading=hd)
    out, pos = cape(L, L.cloth, sash, None, jag=0.36, teeth=6, rag=0.35, hem_glow=True, flare=0.4, seed=13)
    for vx, z in ((-0.5, 0.6), (0.4, 0.2), (-0.2, -0.5), (0.6, -0.9), (-0.6, -1.2), (0.1, 0.9)):
        crack(L, "UpperTorso", out, (-vx, -3, z), (0, 1, 0), rnd, length=0.75, width=0.045, branches=2, heading=(rnd.uniform(-0.5, 0.5), 0, -1))
    for cpos, size, d in (((1.32, -0.7, 1.55), 0.17, (0.3, 0, 1)), ((-1.35, -0.75, 1.3), 0.15, (-0.4, 0.1, 1)), ((1.15, -0.95, 0.6), 0.12, (0.6, 0, 1)), ((-1.1, -1.0, 0.45), 0.13, (-0.5, 0, 1))):
        shard(L, "UpperTorso", cpos, size, d)
    skirt = hips(L, {"belt": "blue", "gold": accent, "sash": sash, "gem": L.glowm, "pouches": False, "bandolier": False})
    crack(L, "LowerTorso", skirt, (0.5, 3, -0.95), (0, -1, 0), rnd, length=0.4, width=0.03, branches=1, heading=(1, 0, -0.2))
    arm(L, {"armored": True, "stitch": accent, "sash": sash, "pads": False, "bracer": obsid})
    sh = dome_pauldron(L, plum, accent, under=obsid, gem=False, rim_glow=True)
    for i, (dy, ln, lean) in enumerate(((0.0, 0.46, 0.3), (0.28, 0.32, 0.5), (-0.28, 0.32, 0.5), (0.0, 0.26, 1.0))):
        hp, hn = hit(sh, (1.62 + lean * 0.25, dy, 4), (0, 0, -1))
        if hp is not None:
            d = Vector((lean, dy * 0.6, 1)).normalized()
            shard(L, "RightUpperArm", hp + d * ln * 0.45, ln * 0.55, d, mat=obsid)
            shard(L, "RightUpperArm", hp + d * ln * 0.75, ln * 0.3, d)
    crack(L, "RightUpperArm", sh, (1.47 + 3, 0, 0.9), (-1, 0, 0), rnd, length=0.4, width=0.03, branches=1)
    up, br = arm_parts(L)
    crack(L, "RightLowerArm", br, (1.43 + 3, 0, -0.2), (-1, 0, 0), rnd, length=0.5, width=0.035, branches=1, heading=(0, 0.3, -1))
    crack(L, "RightLowerArm", br, (1.43, 3, -0.3), (0, -1, 0), rnd, length=0.4, width=0.03, branches=1, heading=(0, 0, -1))
    leg(L, {"wraps": True, "x": accent, "sash": sash})
    th = named(L, "RightUpperLeg", "Thigh")
    crack(L, "RightUpperLeg", th, (0.49 + 3, 0, -1.1), (-1, 0, 0), rnd, length=0.7, branches=2, heading=(0, 0.2, -1))
    crack(L, "RightUpperLeg", th, (0.3, 3, -1.2), (0, -1, 0), rnd, length=0.5, branches=1, heading=(0.3, 0, -1))
    boot = named(L, "RightFoot", "Boot")
    crack(L, "RightFoot", boot, (0.6, 3, -2.7), (0, -1, 0), rnd, length=0.3, width=0.03, branches=1, heading=(1, 0, 0.2))
    return L


TIERS = {"brown": brown, "green": green, "blue": blue, "purple": purple, "red": red, "black": black, "white": white,
         "gold": gold, "crimson": crimson, "shadow": shadow, "celestial": celestial, "void": void}


# ---------------------------------------------------------------- bake + export
def mirror_limbs(L):
    for region in list(REGIONS):
        if region.startswith("Right"):
            left = "Left" + region[5:]
            for kind in ("parts", "glow"):
                src = getattr(L, kind)[region]
                getattr(L, kind)[left] = [H.mirror_x(o, o.name.replace("Right", "") + "_L") for o in src]


MAX_TRIS = 19000


def finish(L):
    name = "HeroNinja_" + L.tier
    atlas = [o for r in REGIONS if not r.startswith("Left") for o in L.parts[r]]
    weights = {o.name: 1.9 for o in L.parts["Head"]}
    if not FAST:
        bake.bake_atlas(atlas, os.path.join(TEX, name + ".png"), name, size=1024, ao=0.42, ao_distance=0.15, ao_samples=160, weights=weights)
    mirror_limbs(L)
    layout, shipped = [], []
    for region, (center, size, ref) in REGIONS.items():
        for kind, suffix in (("parts", ""), ("glow", "__Glow")):
            objs = getattr(L, kind)[region]
            if not objs:
                continue
            o = C.merge(objs, "%s_%s%s" % (name, region, suffix))
            if "Decal" in o.data.uv_layers:
                o.data.uv_layers.remove(o.data.uv_layers["Decal"])
            H.triangulate(o)
            n = len(o.data.polygons)
            if n > MAX_TRIS:  # Roblox rejects meshes over 20k triangles
                m = o.modifiers.new("Decimate", "DECIMATE")
                m.ratio = MAX_TRIS / n * 0.97
                C.apply_modifiers(o)
                H.triangulate(o)
            C.shade_auto(o, 50)
            layout.append(o)
            # a copy placed in the layout for the preview; the shipped one is normalised
            s = o.copy()
            s.data = o.data.copy()
            bpy.context.scene.collection.objects.link(s)
            final = o.name
            o.name = final + "_layout"
            s.name = final
            s.data.name = final
            k = Vector(ref[i] / size[i] for i in range(3))
            s.data.transform(Matrix.Diagonal((k.x, k.y, k.z, 1)) @ Matrix.Translation(-Vector(center)))
            shipped.append(s)
    return layout, shipped


def main():
    C.reset_scene()
    shipped = []
    for tier, fn in TIERS.items():
        if ONLY and tier not in ONLY:
            continue
        L = fn()
        layout, ship = finish(L)
        shipped += ship
        q = {"samples": 12} if FAST else {}
        H.studio_render(os.path.join(PREV, "ninja_" + tier + ".png"), layout, view=(0, 1, 0), up=(0, 0, 1), size=(800, 1600), margin=1.1, **q)
        H.studio_render(os.path.join(PREV, "ninja_" + tier + "_34.png"), layout, view=(-0.8, 1, 0.25), up=(0, 0, 1), size=(800, 1600), margin=1.1, ortho=False, **q)
        if os.environ.get("HERO_BACK") == "1":  # look-dev: check capes and backs
            H.studio_render(os.path.join(PREV, "ninja_" + tier + "_back.png"), layout, view=(0.7, -1, 0.3), up=(0, 0, 1), size=(800, 1600), margin=1.1, ortho=False, **q)
        for o in layout:
            o.hide_render = True
            o.location.x += 50
    C.write_manifest(os.path.join(OUT, "HeroNinjas.lua"), "hero_ninjas.py", shipped,
                     "each piece is centred on its R15 part and sized for the default R15 part (SUIT_REF)")
    C.export_fbx(os.path.join(OUT, "NinjaSim_HeroNinjas.fbx"), shipped, embed=True)
    for o in shipped:
        print("MESH", o.name, sum(len(p.vertices) - 2 for p in o.data.polygons), "tris")


if __name__ == "__main__":
    main()
