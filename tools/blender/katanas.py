"""NinjaSim katana kit: blades, edges, guards, collar, grip, wrap and pommels.

All pieces are modelled in one shared frame (grip centred on the origin, blade
toward Blender +Y = Roblox -Z), so the game can mix any blade with any guard.
Run: python3 tools/blender/katanas.py <out_dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
import common as C  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/katanas"
os.makedirs(OUT, exist_ok=True)
C.reset_scene()

STEEL = C.material("Steel", (0.72, 0.75, 0.8), metallic=0.75, roughness=0.25)
EDGE = C.material("Edge", (0.95, 0.97, 1.0), metallic=0.6, roughness=0.12)
GOLD = C.material("Gold", (0.85, 0.62, 0.22), metallic=0.8, roughness=0.3)
CLOTH = C.material("Cloth", (0.12, 0.1, 0.16), roughness=0.9)
WRAP = C.material("Wrap", (0.55, 0.12, 0.12), roughness=0.8)
GEM = C.material("Gem", (0.3, 0.8, 1.0), roughness=0.05, emission=(0.3, 0.8, 1.0), strength=3)

GRIP_HALF = 0.5
GUARD_Y = GRIP_HALF + 0.05
COLLAR_Y = GUARD_Y + 0.1
BLADE_Y = COLLAR_Y + 0.08
objects = []


def keep(o):
    objects.append(o)
    return o


# ---------------------------------------------------------------- blades
def blade(style, length=3.6, width=0.27, thick=0.075, curve=0.2):
    """Returns (body, edge) for one blade style."""
    stations = 70
    tip_frac = {"Standard": 0.11, "Wide": 0.14, "Straight": 0.08, "Jagged": 0.12}[style]
    if style == "Wide":
        width, thick, curve = width * 1.45, thick * 1.15, curve * 0.8
    if style == "Straight":
        curve = 0.0
    body_v, edge_v, body_rings, edge_rings = [], [], [], []
    for i in range(stations + 1):
        t = i / stations
        y = BLADE_Y + t * length
        rise = curve * t * t
        w = width * (1 - 0.22 * t) if style != "Wide" else width * (1 - 0.1 * t)
        th = thick * (1 - 0.35 * t)
        top = w / 2 + rise
        if style == "Jagged" and 0.18 < t < 0.86:
            saw = (t * 22) % 1.0
            top += w * 0.22 * (1 - saw)
        bot = top - w
        if style == "Jagged" and 0.18 < t < 0.86:
            bot = rise - w / 2
        # kissaki: the edge sweeps up to meet the spine
        k = 1.0
        if t > 1 - tip_frac:
            u = (t - (1 - tip_frac)) / tip_frac
            if style == "Straight":
                k = max(0.0, 1 - u)  # chisel point
            else:
                k = max(0.0, 1 - u ** 1.7)
            span = (top - bot) * k
            bot = top - span
            th *= max(0.05, 1 - u * 0.9)
        span = top - bot
        shin = top - span * 0.3
        hamon = bot + span * (0.3 + 0.05 * math.sin(t * 46) + 0.02 * math.sin(t * 131))
        tb, tsn, th_h, e = th * 0.28, th * 0.5, th * 0.34, max(0.004, th * 0.04)
        b0 = len(body_v)
        body_v += [(tb, y, top), (tsn, y, shin), (th_h, y, hamon), (-th_h, y, hamon), (-tsn, y, shin), (-tb, y, top)]
        body_rings.append(list(range(b0, b0 + 6)))
        e0 = len(edge_v)
        edge_v += [(th_h, y, hamon), (e, y, bot), (-e, y, bot), (-th_h, y, hamon)]
        edge_rings.append(list(range(e0, e0 + 4)))
    body = C.mesh_object("KatanaBlade_" + style, body_v, C.loft(body_rings), STEEL)
    edge = C.mesh_object("KatanaEdge_" + style, edge_v, C.loft(edge_rings), EDGE)
    for o in (body, edge):
        C.recalc_normals(o)
        C.shade_auto(o, 25)
    return keep(body), keep(edge)


for s in ("Standard", "Wide", "Straight", "Jagged"):
    blade(s)


# ---------------------------------------------------------------- guards (tsuba)
def polar(fn, n=72):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        r = fn(a)
        pts.append((r * math.cos(a), r * math.sin(a)))
    return pts


def rounded_square(h, r, n=10):
    pts = []
    for cx, cz, start in ((h - r, h - r, 0), (-(h - r), h - r, 90), (-(h - r), -(h - r), 180), (h - r, -(h - r), 270)):
        for i in range(n + 1):
            a = math.radians(start + 90 * i / n)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


GUARDS = {
    "Round": polar(lambda a: 0.3),
    "Square": rounded_square(0.27, 0.08),
    "Flower": polar(lambda a: 0.25 + 0.06 * abs(math.cos(2 * a)) ** 0.6, 96),
    "Crescent": polar(lambda a: 0.24 + 0.16 * max(0.0, math.sin(a)) ** 5 + 0.05 * max(0.0, -math.sin(a)) ** 2, 96),
    "Spiked": [p for i in range(16) for p in [((0.36 if i % 2 == 0 else 0.2) * math.cos(math.pi * i / 8), (0.36 if i % 2 == 0 else 0.2) * math.sin(math.pi * i / 8))]],
    "Wings": polar(lambda a: 0.2 + 0.24 * abs(math.cos(a)) ** 3 * (1 + 0.25 * math.sin(a)), 96),
}
for name, outline in GUARDS.items():
    g = C.extrude_outline("KatanaGuard_" + name, outline, 0.07, GOLD, axis="Y", bevel=0.012)
    # raised centre boss (seppa) so the guard reads as forged, not a flat plate
    boss = C.extrude_outline("tmp_boss", [(x * 0.5, z * 0.5) for (x, z) in outline], 0.1, GOLD, axis="Y", bevel=0.01)
    g.location.y = GUARD_Y
    boss.location.y = GUARD_Y
    C.apply_transforms([g, boss])
    g = C.join([g, boss], "KatanaGuard_" + name)
    C.shade_auto(g, 40)
    keep(g)

# Ring guard: a torus with a cross brace
bpy.ops.mesh.primitive_torus_add(major_radius=0.25, minor_radius=0.045, major_segments=48, minor_segments=12, location=(0, GUARD_Y, 0), rotation=(math.pi / 2, 0, 0))
ring = bpy.context.active_object
cross = C.extrude_outline("tmp_cross", [(-0.25, -0.05), (0.25, -0.05), (0.25, 0.05), (-0.25, 0.05)], 0.05, GOLD, axis="Y")
cross.location.y = GUARD_Y
cross2 = C.extrude_outline("tmp_cross2", [(-0.05, -0.25), (0.05, -0.25), (0.05, 0.25), (-0.05, 0.25)], 0.05, GOLD, axis="Y")
cross2.location.y = GUARD_Y
hub = C.lathe("tmp_hub", [(0.0, GUARD_Y - 0.045), (0.09, GUARD_Y - 0.045), (0.09, GUARD_Y + 0.045), (0.0, GUARD_Y + 0.045)], 24, GOLD)
C.apply_transforms([ring, cross, cross2, hub])
ringg = C.join([ring, cross, cross2, hub], "KatanaGuard_Ring")
ringg.data.materials.clear()
ringg.data.materials.append(GOLD)
for p in ringg.data.polygons:
    p.use_smooth = True
keep(ringg)

# ---------------------------------------------------------------- collar (habaki)
col = C.extrude_outline("KatanaCollar", [(-0.07, -0.16), (0.07, -0.16), (0.075, 0.16), (-0.075, 0.16)], 0.16, GOLD, axis="Y", bevel=0.015)
col.location.y = COLLAR_Y
C.apply_transforms([col])
keep(col)


# ---------------------------------------------------------------- grip (tsuka) + wrap (ito)
def oval_ring(rx, rz, y, n=20):
    return [(rx * math.cos(2 * math.pi * i / n), y, rz * math.sin(2 * math.pi * i / n)) for i in range(n)]


verts, rings = [], []
for i in range(13):
    t = i / 12
    y = -GRIP_HALF + t
    swell = 1 + 0.08 * math.cos((t - 0.5) * math.pi * 2) * 0.5 + 0.04
    ring_pts = oval_ring(0.095 * swell, 0.12 * swell, y)
    rings.append(list(range(len(verts), len(verts) + len(ring_pts))))
    verts += ring_pts
grip = C.mesh_object("KatanaGrip", verts, C.loft(rings), CLOTH, smooth=True)
C.recalc_normals(grip)
keep(grip)


def ribbon(direction, turns=4.5, width=0.075, n=220):
    v, f = [], []
    for i in range(n + 1):
        t = i / n
        y = -GRIP_HALF + 0.06 + t * (2 * GRIP_HALF - 0.12)
        a = direction * 2 * math.pi * turns * t
        swell = 1 + 0.08 * math.cos((t - 0.5) * math.pi * 2) * 0.5 + 0.05
        for side in (-0.5, 0.5):
            yy = y + side * width
            v.append((0.105 * swell * math.cos(a), yy, 0.13 * swell * math.sin(a)))
    for i in range(n):
        a, b = 2 * i, 2 * i + 2
        f.append((a, b, b + 1, a + 1))
    return v, f


v1, f1 = ribbon(1)
v2, f2 = ribbon(-1)
off = len(v1)
wrap = C.mesh_object("KatanaWrap", v1 + v2, f1 + [(a + off, b + off, c + off, d + off) for (a, b, c, d) in f2], WRAP, smooth=True)
solid = wrap.modifiers.new("Solid", "SOLIDIFY")
solid.thickness = 0.018
C.apply_modifiers(wrap)
keep(wrap)

# ---------------------------------------------------------------- pommels (kashira) + gem + tassel
cap_profile = [(0.0, -GRIP_HALF - 0.1), (0.07, -GRIP_HALF - 0.095), (0.11, -GRIP_HALF - 0.06), (0.125, -GRIP_HALF - 0.02), (0.125, -GRIP_HALF + 0.02)]
cap = C.lathe("tmp_cap", [(r, h) for r, h in cap_profile], 24, GOLD)
cap.scale = (0.85, 1, 1)
C.apply_transforms([cap])
cap.name = "KatanaPommel_Cap"
keep(cap)

bpy.ops.mesh.primitive_torus_add(major_radius=0.1, minor_radius=0.022, major_segments=32, minor_segments=10, location=(0, -GRIP_HALF - 0.2, 0), rotation=(0, math.pi / 2, 0))
pring = bpy.context.active_object
pring.name = "KatanaPommel_Ring"
pring.data.materials.append(GOLD)
C.apply_transforms([pring])
keep(pring)

bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.09, radius2=0.0, depth=0.1, location=(0, -GRIP_HALF - 0.16, 0), rotation=(math.pi / 2, 0, 0))
setting = bpy.context.active_object
setting.name = "KatanaPommel_Setting"
setting.data.materials.append(GOLD)
C.apply_transforms([setting])
keep(setting)

# gem: a cut octahedron
gv = [(0, 0, 0.1), (0, 0, -0.1)] + [(0.07 * math.cos(a), 0.07 * math.sin(a), 0) for a in [i * math.pi / 4 for i in range(8)]]
gf = [(0, 2 + i, 2 + (i + 1) % 8) for i in range(8)] + [(1, 2 + (i + 1) % 8, 2 + i) for i in range(8)]
gem = C.mesh_object("KatanaGem", [(x, y - GRIP_HALF - 0.25, z) for (x, z, y) in gv], gf, GEM)
C.recalc_normals(gem)
keep(gem)

# tassel: cord loop + knot + fanned strands
parts = []
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, segments=12, ring_count=8, location=(0, -GRIP_HALF - 0.14, -0.2))
parts.append(bpy.context.active_object)
bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.012, depth=0.18, location=(0, -GRIP_HALF - 0.12, -0.1))
parts.append(bpy.context.active_object)
bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.07, radius2=0.03, depth=0.32, location=(0, -GRIP_HALF - 0.16, -0.4))
parts.append(bpy.context.active_object)
C.apply_transforms(parts)
tassel = C.join(parts, "KatanaTassel")
tassel.data.materials.append(WRAP)
keep(tassel)

for o in objects:
    o.data.name = o.name

C.write_manifest(os.path.join(OUT, "KatanaManifest.lua"), "katanas.py", objects, "grip centred on the origin; blades point toward -Z")
C.export_fbx(os.path.join(OUT, "NinjaSim_Katanas.fbx"), objects)

# previews: every blade with a different guard / pommel, laid out side by side
import bpy as _b  # noqa
kits = [
    ("Standard", "Round", "Cap"), ("Wide", "Spiked", "Cap"), ("Straight", "Square", "Ring"), ("Jagged", "Wings", "Setting"),
]
shown = []
for row, (bl, gd, pm) in enumerate(kits):
    names = ["KatanaBlade_" + bl, "KatanaEdge_" + bl, "KatanaGuard_" + gd, "KatanaCollar", "KatanaGrip", "KatanaWrap", "KatanaPommel_Cap"]
    if pm != "Cap":
        names.append("KatanaPommel_" + pm)
    if pm == "Setting":
        names.append("KatanaGem")
    if row == 1:
        names.append("KatanaTassel")
    for n in names:
        src = _b.data.objects[n]
        dup = src.copy()
        dup.data = src.data.copy()
        dup.name = "prev_%d_%s" % (row, n)
        _b.context.scene.collection.objects.link(dup)
        dup.location.z -= row * 0.9
        shown.append(dup)
for o in _b.data.objects:
    if o.type == "MESH":
        o.hide_render = o not in shown
C.render_preview(os.path.join(OUT, "preview_katanas.png"), shown, size=(1400, 800), camera_dir=(1.0, 0.0, 0.0), ortho=True, margin=1.08, samples=32)
guards = [o for o in objects if o.name.startswith("KatanaGuard_")]
shown = []
for i, g in enumerate(guards):
    dup = g.copy()
    dup.data = g.data.copy()
    _b.context.scene.collection.objects.link(dup)
    dup.location.x += (i - len(guards) / 2) * 0.85
    shown.append(dup)
for o in _b.data.objects:
    if o.type == "MESH":
        o.hide_render = o not in shown
C.render_preview(os.path.join(OUT, "preview_guards.png"), shown, size=(1400, 400), camera_dir=(0.0, -1.0, 0.25), ortho=True, margin=1.1, samples=32)
print("OK", len(objects), "objects")
