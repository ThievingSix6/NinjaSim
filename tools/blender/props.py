"""NinjaSim village props: torii, houses, pagoda, lanterns, trees, rocks, bushes,
fences and bamboo. Each prop stands on its own origin (ground level, facing
Roblox -Z) and is split into colour groups named "<Prop>__<Group>" so the game
can recolour pieces per zone. Run: python3 tools/blender/props.py <out_dir>
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
import common as C  # noqa: E402
import sculpt as S  # noqa: E402
from common import rgb  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.noise import noise as perlin  # noqa: E402
from shapes import ribbon  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/props"
os.makedirs(OUT, exist_ok=True)
C.reset_scene()

M = {
    "red": C.material("ToriiRed", rgb(200, 40, 32), roughness=0.55, roblox="Wood"),
    "black": C.material("Lacquer", rgb(34, 28, 28), roughness=0.4, roblox="Wood"),
    "stone": C.material("Stone", rgb(150, 146, 138), roughness=0.9, roblox="Slate"),
    "wood": C.material("Wood", rgb(112, 72, 44), roughness=0.8, roblox="Wood"),
    "darkwood": C.material("DarkWood", rgb(70, 44, 30), roughness=0.8, roblox="Wood"),
    "plaster": C.material("Plaster", rgb(236, 226, 206), roughness=0.95, roblox="Plaster"),
    "shoji": C.material("Shoji", rgb(250, 238, 205), roughness=0.9, emission=rgb(255, 220, 160), strength=0.4, roblox="SmoothPlastic"),
    "roof": C.material("RoofTile", rgb(64, 70, 86), roughness=0.6, roblox="Slate"),
    "gold": C.material("Gold", rgb(226, 184, 80), metallic=0.8, roughness=0.3, roblox="Foil"),
    "paper": C.material("Paper", rgb(235, 70, 50), roughness=0.9, emission=rgb(255, 120, 70), strength=2.0, roblox="Neon"),
    "glow": C.material("Glow", rgb(255, 196, 120), emission=rgb(255, 196, 120), strength=4.0, roblox="Neon"),
    "bark": C.material("Bark", rgb(96, 66, 50), roughness=0.95, roblox="Wood"),
    "sakura": C.material("Sakura", rgb(255, 178, 204), roughness=0.9, roblox="Grass"),
    "pine": C.material("Pine", rgb(60, 120, 64), roughness=0.9, roblox="Grass"),
    "leaf": C.material("Leaf", rgb(88, 152, 72), roughness=0.9, roblox="Grass"),
    "rock": C.material("Rock", rgb(128, 124, 118), roughness=0.95, roblox="Slate"),
    "bamboo": C.material("Bamboo", rgb(120, 170, 70), roughness=0.6, roblox="SmoothPlastic"),
    "cloth": C.material("Cloth", rgb(250, 245, 235), roughness=0.9, roblox="Fabric"),
}
objects = []


def keep(o, name=None):
    if name:
        o.name = name
    o.data.name = o.name
    objects.append(o)
    return o


def group(prop, name, parts, mat):
    return keep(C.merge(parts, prop + "__" + name, M[mat]))


# ------------------------------------------------------------- curved roof
def curved_roof(name, width, depth, height, overhang=1.5, flick=1.2, thick=0.45, center=(0, 0, 0), hip=False, nu=14, nv=10, tile=0.0):
    """Gable roof with concave slopes and upturned eaves. Ridge along X.
    tile > 0 adds rounded tile rows (that spacing apart) running down the slope."""
    cx, cy, cz = center
    hw, hd = width / 2 + overhang, depth / 2 + overhang
    verts, faces = [], []

    def height_at(u, x):
        # u: 0 at ridge -> 1 at eave; concave profile + corner flick
        y = height * (1 - u) ** 1.55 + (u * 0) - height * 0.0
        corner = (abs(x) / hw) ** 6
        rows = 0.16 * abs(math.sin(math.pi * x / tile)) if tile else 0.0
        return y + flick * corner * u ** 2 + rows

    for side in (-1, 1):
        base = len(verts)
        for i in range(nu + 1):
            x = -hw + 2 * hw * i / nu
            for j in range(nv + 1):
                u = j / nv
                z = side * u * hd
                verts.append((cx + x, cy + z, cz + height_at(u, x)))
        for i in range(nu):
            for j in range(nv):
                a = base + i * (nv + 1) + j
                b = a + nv + 1
                faces.append((a, b, b + 1, a + 1) if side > 0 else (a, a + 1, b + 1, b))
    o = C.mesh_object(name, verts, faces, M["roof"], smooth=True)
    sol = o.modifiers.new("S", "SOLIDIFY")
    sol.thickness = thick
    sol.offset = -1
    C.apply_modifiers(o)
    C.recalc_normals(o)
    return o


def roof_ridge(name, width, height, center, overhang=1.5):
    cx, cy, cz = center
    r = C.box(name, (width + overhang * 2 + 0.6, 0.9, 0.7), (cx, cy, cz + height + 0.1), M["roof"], bevel=0.12)
    caps = []
    for sx in (-1, 1):
        caps.append(C.box(name + "c%d" % sx, (0.9, 1.2, 1.3), (cx + sx * (width / 2 + overhang + 0.3), cy, cz + height + 0.4), M["roof"], bevel=0.15))
    return [r] + caps


# ------------------------------------------------------------- torii (16 wide x 16 tall)
def torii():
    W, H = 16.0, 16.0
    red, black, stone = [], [], []
    for sx in (-1, 1):
        red.append(C.cylinder("p", 0.9, H - 0.4, (sx * W / 2, 0, 0.9), M["red"], 20, radius_top=0.78))
        black.append(C.cylinder("b", 1.25, 1.2, (sx * W / 2, 0, 0), M["black"], 20, radius_top=1.05))
        stone.append(C.cylinder("s", 1.6, 0.35, (sx * W / 2, 0, -0.2), M["stone"], 16))
    # nuki (lower beam) and shimaki
    red.append(C.box("nuki", (W + 3.2, 1.0, 1.1), (0, 0, H * 0.74), M["red"], bevel=0.08))
    red.append(C.box("shimaki", (W + 5.0, 1.5, 1.1), (0, 0, H - 0.6), M["red"], bevel=0.1))
    # kasagi: curved top beam with upswept ends
    n = 24
    v, f = [], []
    length = W + 8.0
    for i in range(n + 1):
        t = -1 + 2 * i / n
        x = t * length / 2
        lift = 0.9 * abs(t) ** 2.6
        for (dy, dz) in ((-1.1, 0.0), (1.1, 0.0), (1.1, 1.15), (-1.1, 1.15)):
            v.append((x, dy * (1 - 0.1 * abs(t)), H + 0.2 + lift + dz))
    rings = [list(range(4 * i, 4 * i + 4)) for i in range(n + 1)]
    kasagi = C.mesh_object("kasagi", v, C.loft(rings), M["black"])
    C.recalc_normals(kasagi)
    black.append(kasagi)
    # gakuzuka (centre strut) + plaque
    red.append(C.box("strut", (0.8, 0.7, H * 0.26), (0, 0, H * 0.87), M["red"]))
    black.append(C.box("plaque", (2.0, 0.5, 2.8), (0, -0.55, H * 0.87), M["black"], bevel=0.1))
    group("Torii", "Red", red, "red")
    group("Torii", "Black", black, "black")
    group("Torii", "Stone", stone, "stone")


# ------------------------------------------------------------- stone lantern (toro)
def stone_lantern():
    parts = []
    parts.append(C.lathe("base", [(0.0, 0.0), (1.4, 0.0), (1.35, 0.35), (1.0, 0.55), (0.0, 0.55)], 6, M["stone"], axis="Z", smooth=False))
    parts.append(C.cylinder("post", 0.45, 2.4, (0, 0, 0.55), M["stone"], 12, radius_top=0.38))
    parts.append(C.lathe("tray", [(0.0, 2.9), (0.7, 2.9), (1.15, 3.2), (1.15, 3.4), (0.0, 3.4)], 6, M["stone"], axis="Z", smooth=False))
    # firebox: 4 corner posts
    for a in range(6):
        ang = a * math.pi / 3
        parts.append(C.box("fb%d" % a, (0.28, 0.28, 1.2), (0.78 * math.cos(ang), 0.78 * math.sin(ang), 4.0), M["stone"]))
    # roof: flared hexagonal cap with knob
    parts.append(C.lathe("roof", [(0.0, 4.6), (1.75, 4.6), (1.9, 4.75), (0.9, 5.45), (0.35, 5.7), (0.0, 5.7)], 6, M["stone"], axis="Z", smooth=False))
    parts.append(C.lathe("knob", [(0.0, 5.65), (0.28, 5.75), (0.35, 6.0), (0.18, 6.35), (0.0, 6.45)], 10, M["stone"], axis="Z"))
    group("StoneLantern", "Stone", parts, "stone")
    group("StoneLantern", "Glow", [C.lathe("fire", [(0.0, 3.45), (0.62, 3.45), (0.62, 4.55), (0.0, 4.55)], 6, M["glow"], axis="Z", smooth=False)], "glow")


# ------------------------------------------------------------- paper lantern on a post
def paper_lantern():
    wood = [C.cylinder("post", 0.22, 7.2, (0, 0, 0), M["darkwood"], 10), C.box("arm", (2.2, 0.3, 0.3), (1.0, 0, 7.0), M["darkwood"])]
    prof = []
    for i in range(61):
        t = i / 60
        z = 4.6 + t * 1.9
        r = 0.2 + 0.85 * math.sin(t * math.pi) ** 0.7
        r += 0.035 * abs(math.sin(t * math.pi * 10))  # bamboo ribs under the paper
        prof.append((r, z))
    lamp = C.lathe("lamp", [(0.0, 4.55)] + prof + [(0.0, 6.55)], 24, M["paper"], axis="Z")
    lamp.location.x = 1.8
    caps = [C.cylinder("capb", 0.45, 0.22, (1.8, 0, 4.42), M["black"], 12), C.cylinder("capt", 0.45, 0.22, (1.8, 0, 6.5), M["black"], 12)]
    C.apply_transforms([lamp])
    group("PaperLantern", "Wood", wood, "darkwood")
    group("PaperLantern", "Paper", [lamp], "paper")
    group("PaperLantern", "Black", caps, "black")


# ------------------------------------------------------------- house (minka) 16 x 12, walls 9
def house():
    W, D, H = 16.0, 12.0, 9.0
    base = [C.box("plinth", (W + 2.4, D + 2.4, 1.2), (0, 0, 0.6), M["stone"], bevel=0.15)]
    wood, plaster, shoji = [], [], []
    # engawa (veranda) boards along the front
    wood.append(C.box("engawa", (W + 1.0, 2.2, 0.35), (0, -D / 2 - 0.9, 1.55), M["wood"]))
    plaster.append(C.box("walls", (W, D, H), (0, 0, 1.2 + H / 2), M["plaster"]))
    # timber frame: posts + beams
    for sx in (-1, 0, 1):
        for sy in (-1, 1):
            wood.append(C.box("post", (0.8, 0.8, H + 0.4), (sx * W / 2 * (1 if sx else 0), sy * D / 2, 1.2 + H / 2), M["wood"]))
    for z in (1.2 + H * 0.12, 1.2 + H * 0.62, 1.2 + H - 0.3):
        for sy in (-1, 1):
            wood.append(C.box("beam", (W + 0.6, 0.7, 0.55), (0, sy * D / 2 + sy * 0.12, z), M["wood"]))
        for sx in (-1, 1):
            wood.append(C.box("beamx", (0.7, D + 0.6, 0.55), (sx * W / 2 + sx * 0.12, 0, z), M["wood"]))
    # sliding shoji panels on the front with lattice
    for i, x in enumerate((-4.6, -1.6, 1.6, 4.6)):
        shoji.append(C.box("shoji%d" % i, (2.8, 0.15, 4.8), (x, -D / 2 - 0.12, 1.2 + H * 0.12 + 2.7), M["shoji"]))
        for k in range(1, 4):
            wood.append(C.box("lat", (2.8, 0.2, 0.12), (x, -D / 2 - 0.22, 1.2 + H * 0.12 + 0.3 + k * 1.2), M["darkwood"]))
        wood.append(C.box("latv", (0.12, 0.2, 4.8), (x, -D / 2 - 0.22, 1.2 + H * 0.12 + 2.7), M["darkwood"]))
    roof = curved_roof("roof", W + 1, D + 1, 5.5, overhang=2.4, flick=1.4, center=(0, 0, 1.2 + H), nu=132, nv=12, tile=0.95)
    ridge = roof_ridge("ridge", W + 1, 5.5, (0, 0, 1.2 + H), overhang=2.4)
    # gable end boards
    for sx in (-1, 1):
        wood.append(C.box("gable", (0.35, D * 0.9, 0.5), (sx * (W / 2 + 0.3), 0, 1.2 + H + 0.2), M["wood"]))
    group("House", "Base", base, "stone")
    group("House", "Wood", wood, "wood")
    group("House", "Walls", plaster, "plaster")
    group("House", "Shoji", shoji, "shoji")
    group("House", "Roof", [roof] + ridge, "roof")


# ------------------------------------------------------------- pagoda (stackable tier, base 26)
def hip_roof(name, size, height, overhang=4.2, flick=2.2, thick=0.5, center=(0, 0, 0), n=12, nv=12, tile=0.0):
    """Four-sided pagoda eave: concave slopes rising to a small top, corners swept up.
    tile > 0 adds rounded tile rows running down each face."""
    cx, cy, cz = center
    a0, a1 = size / 2 + overhang, size * 0.1
    verts, rings = [], []
    # square perimeter in [-1, 1], n points per side
    perim = []
    for side in range(4):
        for i in range(n):
            t = -1 + 2 * i / n
            perim.append([(t, -1), (1, t), (-t, 1), (-1, -t)][side])
    for j in range(nv + 1):
        u = j / nv  # 0 at the eave, 1 at the top
        a = a0 + (a1 - a0) * u
        z = height * u ** 1.7
        ring = []
        for (px, py) in perim:
            c = (abs(px) * abs(py)) ** 2  # 1 at corners, 0 mid-edge
            out = 1 + 0.07 * c * (1 - u) ** 2
            along = py if abs(px) >= abs(py) else px
            rows = 0.18 * abs(math.sin(math.pi * along * a / tile)) * (1 - c) if tile else 0.0
            ring.append(len(verts))
            verts.append((cx + px * a * out, cy + py * a * out, cz + z + flick * c * (1 - u) ** 2.2 + rows))
        rings.append(ring)
    faces = C.loft(rings, cap_start=False, cap_end=True)
    o = C.mesh_object(name, verts, faces, M["roof"], smooth=True)
    sol = o.modifiers.new("S", "SOLIDIFY")
    sol.thickness = thick
    sol.offset = -1
    C.apply_modifiers(o)
    C.recalc_normals(o)
    return o


PAGODA_TIER_H, PAGODA_ROOF_H = 8.4, 3.6


def pagoda():
    """PagodaBase (plinth + steps), PagodaTier (walls, red trim, roof) and PagodaTop (gold spire).
    The game stacks tiers, shrinking each, so one mesh set serves 3, 4 or 5 storeys."""
    base_w = 26.0
    stone = [C.box("plinth", (base_w + 8, base_w + 8, 4), (0, 0, 2), M["stone"], bevel=0.3)]
    for i in range(5):
        stone.append(C.box("step%d" % i, (8, 4.0 - i * 0.8, 0.8), (0, -(base_w + 8) / 2 - (4.0 - i * 0.8) / 2, 0.4 + i * 0.8), M["stone"]))
    group("PagodaBase", "Stone", stone, "stone")
    size, h = base_w, PAGODA_TIER_H
    walls = [C.box("wall", (size, size, h), (0, 0, h / 2), M["plaster"])]
    wood = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            wood.append(C.box("post", (1.1, 1.1, h), (sx * size / 2, sy * size / 2, h / 2), M["red"]))
    for sy in (-1, 1):
        for z in (h * 0.3, h - 0.4):
            wood.append(C.box("band", (size + 0.6, 0.6, 0.8), (0, sy * size / 2, z), M["red"]))
    for sx in (-1, 1):
        for z in (h * 0.3, h - 0.4):
            wood.append(C.box("bandx", (0.6, size + 0.6, 0.8), (sx * size / 2, 0, z), M["red"]))
    # balcony rail + lattice windows on all four sides
    for k in range(4):
        ang = k * math.pi / 2
        ca, sa = math.cos(ang), math.sin(ang)
        for i in range(-3, 4):
            x = i * size * 0.62 / 7
            wood.append(C.box("lat", (0.3, 0.3, h * 0.36), (0, 0, 0), M["red"]))
            o = wood[-1]
            o.location = (ca * x - sa * (-size / 2 - 0.2), sa * x + ca * (-size / 2 - 0.2), h * 0.62)
            o.rotation_euler.z = ang
    walls_extra = []
    for k in range(4):
        ang = k * math.pi / 2
        win = C.box("win", (size * 0.62, 0.2, h * 0.36), (0, 0, 0), M["plaster"])
        win.location = (-math.sin(ang) * (-size / 2 - 0.1), math.cos(ang) * (-size / 2 - 0.1), h * 0.62)
        win.rotation_euler.z = ang
        walls_extra.append(win)
    roof = hip_roof("roof", size + 1.5, PAGODA_ROOF_H, center=(0, 0, h), n=84, nv=10, tile=1.5)
    group("PagodaTier", "Walls", walls + walls_extra, "shoji")
    group("PagodaTier", "Trim", wood, "red")
    group("PagodaTier", "Roof", [roof], "roof")
    gold = [C.cylinder("spire", 0.55, 8.0, (0, 0, 0), M["gold"], 12, radius_top=0.15)]
    for k in range(5):
        gold.append(C.cylinder("ring%d" % k, 1.0 - k * 0.12, 0.3, (0, 0, 1.4 + k * 1.2), M["gold"], 16))
    gold.append(C.blob("jewel", 0.7, (0, 0, 8.3), M["gold"], subdiv=2, noise=0.0))
    group("PagodaTop", "Gold", gold, "gold")


# ------------------------------------------------------------- trees (height ~14)
def branch(start, end, r0, r1, mat):
    sx, sy, sz = start
    ex, ey, ez = end
    import mathutils
    d = mathutils.Vector((ex - sx, ey - sy, ez - sz))
    o = C.lathe("br", [(0.0, 0.0), (r0, 0.0), (r1, d.length), (0.0, d.length)], 8, mat, axis="Z")
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    o.location = start
    C.apply_transforms([o])
    return o


def tree(kind, seed):
    """Skinned trunk with root flare and branches, and a puffy fused canopy."""
    rnd = random.Random(seed)
    H = 14.0
    pine = kind == "Pine"
    lean = rnd.uniform(-0.8, 0.8)
    top = (lean, 0.3, H * (0.55 if pine else 0.62))
    verts = [(0, 0, -0.6), (0.05, 0.02, 1.2), (lean * 0.35 + (0.6 if pine else 0.0), 0.12, 4.5), top]
    radii = [1.2, 0.95, 0.72, 0.56]
    edges = [(0, 1), (1, 2), (2, 3)]
    for k in range(4):  # root flare
        a = k * math.pi / 2 + rnd.uniform(-0.3, 0.3)
        verts.append((math.cos(a) * 1.9, math.sin(a) * 1.9, -0.25))
        radii.append(0.3)
        edges.append((1, len(verts) - 1))
    tips = []
    for b in range(5 if pine else 4):
        ang = b * math.tau / (5 if pine else 4) + rnd.uniform(-0.4, 0.4)
        reach = rnd.uniform(3.6, 5.0) if pine else rnd.uniform(3.0, 4.6)
        rise = rnd.uniform(0.4, 1.4) if pine else rnd.uniform(1.8, 3.4)
        z0 = top[2] - (b * 0.9 if pine else 0.0)
        mid = (top[0] + math.cos(ang) * reach * 0.5, top[1] + math.sin(ang) * reach * 0.5, z0 + rise * 0.6)
        tip = (top[0] + math.cos(ang) * reach, top[1] + math.sin(ang) * reach, z0 + rise)
        src = 3
        if pine and b:
            verts.append((top[0] * (1 - b * 0.1), top[1], z0))
            radii.append(0.5)
            edges.append((2 if b > 2 else 3, len(verts) - 1))
            src = len(verts) - 1
        verts += [mid, tip]
        radii += [0.36, 0.18]
        edges += [(src, len(verts) - 2), (len(verts) - 2, len(verts) - 1)]
        tips.append(tip)
    leader = (top[0], top[1], top[2] + (2.0 if pine else 3.6))
    verts.append(leader)
    radii.append(0.26)
    edges.append((3, len(verts) - 1))
    tips.append(leader)
    trunk = S.skin("trunk", verts, edges, radii, M["bark"], subdiv=2)
    S.displace(trunk, lambda co, n: 0.06 * math.sin(math.atan2(co.y, co.x) * 9 + co.z * 0.5) + 0.04 * perlin(co * 1.3))
    trunk = S.budget(trunk, 3000)
    mat = {"Sakura": "sakura", "Pine": "pine", "Leafy": "leaf"}[kind]
    blobs = []
    for i, tip in enumerate(tips):
        if pine:  # cloud pads, bonsai style
            r = rnd.uniform(2.2, 2.9)
            blobs.append(S.ellipsoid("pad", (r, r, r * 0.38), (tip[0], tip[1], tip[2] + 0.3), M[mat], segs=24, rings=12))
            blobs.append(S.ellipsoid("pad2", (r * 0.6, r * 0.6, r * 0.36), (tip[0] * 0.9, tip[1] * 0.9, tip[2] + 0.9), M[mat], segs=20, rings=10))
        else:
            for k in range(4):
                off = (tip[0] + rnd.uniform(-1.4, 1.4), tip[1] + rnd.uniform(-1.4, 1.4), tip[2] + rnd.uniform(-0.5, 1.1))
                r = rnd.uniform(1.8, 2.6)
                blobs.append(S.ellipsoid("puff", (r, r, r * 0.86), off, M[mat], segs=20, rings=12))
    if not pine:
        blobs.append(S.ellipsoid("core", (3.4, 3.4, 2.6), (top[0], top[1], top[2] + 3.0), M[mat], segs=24, rings=14))
    crown = S.fuse(blobs, "crown", M[mat], voxel=0.2, smooth=5)
    off = Vector((seed * 5.3, seed * 2.1, 0))
    S.displace(crown, lambda co, n: 0.42 * perlin(co * 0.8 + off) + 0.14 * perlin(co * 2.4 + off))
    crown = S.budget(crown, 5000 if not pine else 4000)
    name = "Tree%s%d" % (kind, seed)
    group(name, "Trunk", [trunk], "bark")
    group(name, "Leaves", [crown], mat)


# ------------------------------------------------------------- rocks, bushes, bamboo, fence
def rocks():
    for i in range(3):
        rnd = random.Random(40 + i)
        parts = [S.ellipsoid("r", (1.0, 0.86, 0.62), (0, 0, 0.3), M["rock"], power=2.6)]
        for k in range(2 + i):
            parts.append(S.ellipsoid("r", (rnd.uniform(0.4, 0.7), rnd.uniform(0.4, 0.6), rnd.uniform(0.3, 0.5)),
                                     (rnd.uniform(-0.6, 0.6), rnd.uniform(-0.5, 0.5), rnd.uniform(0.2, 0.55)), M["rock"], power=2.4))
        r = S.fuse(parts, "rock", M["rock"], voxel=0.05, smooth=3)
        S.displace(r, lambda co, n: 0.12 * perlin(co * 1.6 + Vector((i * 3, 0, 0))) + 0.05 * perlin(co * 4.5))
        r = S.budget(r, 240 + 60 * i)
        for p in r.data.polygons:  # faceted, hand-cut look
            p.use_smooth = False
        keep(r, "Rock%d__Stone" % (i + 1))


def bushes():
    for i in range(2):
        rnd = random.Random(70 + i)
        parts = [S.ellipsoid("b", (r, r, r * 0.8), (rnd.uniform(-1.2, 1.2), rnd.uniform(-1.2, 1.2), 0.9 + rnd.uniform(-0.1, 0.5)), M["leaf"], segs=18, rings=10)
                 for r in [rnd.uniform(1.1, 1.7) for _ in range(6)]]
        b = S.fuse(parts, "bush", M["leaf"], voxel=0.08, smooth=4)
        S.displace(b, lambda co, n: 0.18 * perlin(co * 1.4 + Vector((i * 4.0, 0, 0))) + 0.06 * perlin(co * 4.0))
        b = S.budget(b, 1800)
        group("Bush%d" % (i + 1), "Leaves", [b], "leaf")


def bamboo():
    stalk, leaves = [], []
    z = 0.0
    for seg in range(8):
        h = 2.6
        stalk.append(C.cylinder("seg", 0.42, h - 0.12, (0, 0, z), M["bamboo"], 10, radius_top=0.4))
        stalk.append(C.cylinder("node", 0.48, 0.14, (0, 0, z + h - 0.14), M["bamboo"], 10))
        z += h
        if seg >= 3:
            for k in range(2):  # a fan of slender leaves on a twig at the node
                ang = seg * 1.7 + k * math.pi
                for j in range(4):
                    a = ang + (j - 1.5) * 0.35
                    pts = []
                    for t in [q / 6 for q in range(7)]:
                        reach = 0.4 + 2.2 * t
                        pts.append((math.cos(a) * reach, math.sin(a) * reach, z - 0.1 + 0.5 * t - 1.1 * t * t))
                    leaves.append(ribbon("lf", pts, [(0, 0, 1)] * 7, [0.08 + 0.4 * math.sin(t * math.pi) ** 0.8 for t in [q / 6 for q in range(7)]], 0.04, M["leaf"]))
    group("Bamboo", "Stalk", stalk, "bamboo")
    group("Bamboo", "Leaves", leaves, "leaf")


def fence():
    # one 8-stud segment along X: two posts, two rails and a cap
    wood = []
    for sx in (-1, 1):
        wood.append(C.box("post", (0.55, 0.55, 3.6), (sx * 4.0, 0, 1.8), M["wood"], bevel=0.06))
        wood.append(C.box("cap", (0.8, 0.8, 0.25), (sx * 4.0, 0, 3.7), M["darkwood"], bevel=0.05))
    for z in (1.3, 2.8):
        wood.append(C.box("rail", (8.3, 0.3, 0.35), (0, 0, z), M["wood"], bevel=0.05))
    group("Fence", "Wood", wood, "wood")


torii()
stone_lantern()
paper_lantern()
house()
pagoda()
for kind, seed in (("Sakura", 1), ("Sakura", 2), ("Pine", 3), ("Leafy", 4)):
    tree(kind, seed)
rocks()
bushes()
bamboo()
fence()

# Props are modelled with their front toward Blender -Y; turn them so the front
# faces Blender +Y, which the FBX axis mapping makes Roblox -Z (forward).
from mathutils import Matrix  # noqa: E402
for o in objects:
    o.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
    o.data.update()
# Each prop's pieces share the prop's own origin; the manifest keeps that frame.
C.write_manifest(os.path.join(OUT, "PropManifest.lua"), "props.py", objects, "each prop stands on its own origin (ground level), front faces -Z")
C.export_fbx(os.path.join(OUT, "NinjaSim_Props.fbx"), objects)

# preview: a little village street
layout = {
    "Torii": (0, 18, 0), "House": (-16, 2, 0.0), "PagodaBase": (26, -26, 0), "StoneLantern": (-6, 12, 0), "PaperLantern": (6, 10, 0),
    "TreeSakura1": (-28, -6, 0), "TreeSakura2": (12, -2, 0), "TreePine3": (-30, 16, 0), "TreeLeafy4": (30, 12, 0),
    "Rock1": (-8, 20, 0), "Rock2": (9, 21, 0), "Rock3": (-20, 18, 0), "Bush1": (-10, 6, 0), "Bush2": (8, 4, 0), "Bamboo": (-38, 4, 0), "Fence": (-4, -14, 0),
}
shown = []
scales = {"Rock1": 2.2, "Rock2": 1.6, "Rock3": 2.6}
for o in list(objects):
    prop = o.name.split("__")[0]
    if prop in layout:
        d = o.copy()
        d.data = o.data.copy()
        bpy.context.scene.collection.objects.link(d)
        s = scales.get(prop, 1.0)
        d.scale = (s, s, s)
        d.location = layout[prop]
        shown.append(d)
tier = [o for o in objects if o.name.startswith("PagodaTier__")]
top = [o for o in objects if o.name.startswith("PagodaTop__")]
y = 4.0
for i in range(3):
    t = 1 - i * 0.16
    for o in tier:
        d = o.copy()
        d.data = o.data.copy()
        bpy.context.scene.collection.objects.link(d)
        d.scale = (t, t, t)
        d.location = (26, -26, y)
        shown.append(d)
    y += (PAGODA_TIER_H + 3.0) * t
for o in top:
    d = o.copy()
    d.data = o.data.copy()
    bpy.context.scene.collection.objects.link(d)
    d.location = (26, -26, y - 0.6)
    shown.append(d)
C.apply_transforms(shown)
ground = C.box("ground", (110, 90, 0.2), (0, 0, -0.1), C.material("Grass", rgb(100, 150, 70), roughness=1))
shown.append(ground)
for o in bpy.data.objects:
    if o.type == "MESH":
        o.hide_render = o not in shown
C.render_preview(os.path.join(OUT, "preview_village.png"), shown, size=(1400, 800), camera_dir=(0.35, 1.0, 0.55), margin=0.78, samples=40, background=(0.55, 0.7, 0.9))
print("OK", len(objects), "objects")
