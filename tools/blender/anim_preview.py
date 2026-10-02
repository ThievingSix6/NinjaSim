"""Renders the katana combo so it can be judged without Studio.

tools/anim/frames.luau samples src/shared/Config/Combo.lua with the game's own pose
code and writes each joint's Transform per frame. This script poses a default R15
rig with them (Part1 = Part0 * C0 * Transform * C1:Inverse(), as Motor6Ds do),
dresses it in the hero ninja suit and katana, and renders:

  <out>/move<N>.png      key frames of each move from the front and from above,
                         with the blade tip's path drawn in
  <out>/combo_*.png      every frame of the whole combo (for a GIF)

Spears (frames.luau ... Spear): a part-built stand-in spear is drawn instead of the
katana, held as CharacterService holds it (Rx(+15) in the hand) and turned by the
"Grip" joint plus each frame's spin; the path drawn is the blade head's tip.
--stats then also prints how far the left hand is from the shaft and how deep the
shaft cuts into the body.

Run: python3 tools/blender/anim_preview.py <frames.json> <out_dir> [--stats] [--gif] [--tier brown] [--katana brown_katana] [--moves 1,2]
"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
flags = [a for a in sys.argv[1:] if a.startswith("--")]
FRAMES, OUT = args[0], args[1]


def flag_value(name, default):
    for i, a in enumerate(sys.argv):
        if a == name and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default


TIER = flag_value("--tier", "brown")
KATANA = flag_value("--katana", "brown_katana")
data = json.load(open(FRAMES))
SPEAR = data.get("weapon") == "Spear"
# stand-in spear (grip space, studs): shaft from the butt behind the hand to the head
SPEAR_BUTT, SPEAR_TIP, SPEAR_HEAD = 2.2, 4.9, 1.3

# ---------------------------------------------------------------- default R15 rig (Roblox space, feet on y = 0)
# part: (centre, parent, joint, pivot)
RIG = {
    "LowerTorso": ((0, 2.91, 0), None, "Root", (0, 2.91, 0)),
    "UpperTorso": ((0, 3.91, 0), "LowerTorso", "Waist", (0, 3.11, 0)),
    "Head": ((0, 5.31, 0), "UpperTorso", "Neck", (0, 4.71, 0)),
}
for side, sx in (("Right", 1), ("Left", -1)):
    RIG[side + "UpperArm"] = ((1.5 * sx, 4.1255, 0), "UpperTorso", side + "Shoulder", (1.0 * sx, 4.45, 0))
    RIG[side + "LowerArm"] = ((1.5 * sx, 3.014, 0), side + "UpperArm", side + "Elbow", (1.5 * sx, 3.54, 0))
    RIG[side + "Hand"] = ((1.5 * sx, 2.338, 0), side + "LowerArm", side + "Wrist", (1.5 * sx, 2.49, 0))
    RIG[side + "UpperLeg"] = ((0.5 * sx, 2.1015, 0), "LowerTorso", side + "Hip", (0.5 * sx, 2.71, 0))
    RIG[side + "LowerLeg"] = ((0.5 * sx, 0.8965, 0), side + "UpperLeg", side + "Knee", (0.5 * sx, 1.49, 0))
    RIG[side + "Foot"] = ((0.5 * sx, 0.15, 0), side + "LowerLeg", side + "Ankle", (0.5 * sx, 0.3, 0))
ORDER = ["LowerTorso", "UpperTorso", "Head"] + [s + p for s in ("Right", "Left") for p in ("UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot")]


def T(x, y, z):
    m = np.eye(4)
    m[:3, 3] = (x, y, z)
    return m


def Rx(deg):
    a = math.radians(deg)
    m = np.eye(4)
    m[1, 1], m[1, 2], m[2, 1], m[2, 2] = math.cos(a), -math.sin(a), math.sin(a), math.cos(a)
    return m


def from_components(c):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c
    m = np.eye(4)
    m[:3, :3] = ((r00, r01, r02), (r10, r11, r12), (r20, r21, r22))
    m[:3, 3] = (x, y, z)
    return m


def solve(joints):
    """World CFrame (4x4, Roblox space) of every part for one frame."""
    world = {}
    for part in ORDER:
        centre, parent, joint, pivot = RIG[part]
        tr = from_components(joints[joint]) if joint in joints else np.eye(4)
        if parent is None:
            p0 = T(*pivot)
            c0 = np.eye(4)
        else:
            p0 = world[parent]
            pc = RIG[parent][0]
            c0 = T(pivot[0] - pc[0], pivot[1] - pc[1], pivot[2] - pc[2])
        c1 = T(pivot[0] - centre[0], pivot[1] - centre[1], pivot[2] - centre[2])
        world[part] = p0 @ c0 @ tr @ np.linalg.inv(c1)
    # CharacterService welds the katana grip to the hand like this
    world["Katana"] = world["RightHand"] @ T(0, -0.075, 0) @ Rx(-30)
    if SPEAR:
        # spears are held at Rx(+15), then turned by the Grip joint and any spin
        grip = from_components(joints["Grip"]) if "Grip" in joints else np.eye(4)
        world["Katana"] = world["RightHand"] @ T(0, -0.075, 0) @ Rx(15) @ grip
    return world


def solve_frame(f):
    world = solve(f["joints"])
    if SPEAR and f.get("spin"):
        world["Katana"] = world["Katana"] @ from_components(f["spin"])
    return world


def blade_points():
    base, tip = (0, 0, -0.74), (0, 0.145, -4.42)
    path = os.path.join(ROOT, "src", "shared", "Visuals", "Manifests", "HeroKatanas.lua")
    import re
    for line in open(path):
        if '"HeroKatana_%s"' % KATANA in line:
            b = re.search(r"BladeBase = Vector3\.new\(([^)]*)\)", line)
            t = re.search(r"BladeTip = Vector3\.new\(([^)]*)\)", line)
            if b and t:
                base = tuple(float(v) for v in b.group(1).split(","))
                tip = tuple(float(v) for v in t.group(1).split(","))
    return np.array((*base, 1.0)), np.array((*tip, 1.0))


BASE, TIP = blade_points()
if SPEAR:
    BASE, TIP = np.array((0, 0, -(SPEAR_TIP - SPEAR_HEAD), 1.0)), np.array((0, 0, -SPEAR_TIP, 1.0))
BODY = {"LowerTorso": (2, 0.4, 1), "UpperTorso": (2, 1.6, 1), "Head": (1.2, 1.2, 1.2)}
for _s in ("Right", "Left"):
    BODY[_s + "UpperLeg"] = (1, 1.2, 1)
    BODY[_s + "LowerLeg"] = (1, 1.2, 1)


def spear_checks(world):
    """(left hand distance from the shaft line, deepest point of the shaft inside the body)"""
    m = world["Katana"]
    o, f = m[:3, 3], -m[:3, 2]
    lp = (world["LeftHand"] @ np.array((0, -0.075, 0, 1.0)))[:3]
    s = (lp - o) @ f
    off = float(np.linalg.norm(lp - o - f * s))
    deep = 0.0
    for k in np.linspace(-SPEAR_BUTT, SPEAR_TIP, 40):
        p = o + f * k
        for part, size in BODY.items():
            local = np.linalg.inv(world[part]) @ np.array((*p, 1.0))
            d = np.array(size) / 2 - np.abs(local[:3])
            if np.all(d > 0):
                deep = max(deep, float(d.min()))
    return off, s, deep


def tip_of(world):
    return (world["Katana"] @ TIP)[:3], (world["Katana"] @ BASE)[:3]


def describe(p):
    """Roblox character space -> readable (right, up, forward)."""
    return "R%+.1f U%+.1f F%+.1f" % (p[0], p[1] - 2.91, -p[2])


if "--stats" in flags:
    for i, move in enumerate(data["moves"], 1):
        print("== move %d  %s" % (i, move["name"]))
        for f in move["frames"]:
            w = solve_frame(f)
            tip, base = tip_of(w)
            d = tip - base
            yaw = math.degrees(math.atan2(-d[0], -d[2]))  # 0 = forward, + = to the left
            elev = math.degrees(math.atan2(d[1], math.hypot(d[0], d[2])))
            mark = " <HIT" if abs(f["t"] - move["hitAt"]) < 0.5 / data["fps"] / move["duration"] else ""
            extra = ""
            if SPEAR:
                off, s, deep = spear_checks(w)
                extra = "  left hand %.2f off shaft (%.1f up it)  in body %.2f" % (off, s, deep)
            print("  t=%.2f w=%.2f tip %s  blade yaw %+4.0f elev %+4.0f%s%s" % (f["t"], f["weight"], describe(tip), yaw, elev, extra, mark))
    sys.exit(0)

# ---------------------------------------------------------------- Blender
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common as C  # noqa: E402

P = np.array(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)), dtype=float)
PINV = np.linalg.inv(P)


def to_blender(m):
    return Matrix((P @ m @ PINV).tolist())


def import_fbx(path, prefix):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before]
    bpy.context.view_layer.update()
    keep = {}
    for o in objs:
        if o.type == "MESH" and o.name.startswith(prefix):
            o.parent = None
    bpy.context.view_layer.update()
    for o in objs:
        if o.type == "MESH" and o.name.startswith(prefix):
            o.data.transform(o.matrix_world)
            o.matrix_world = Matrix.Identity(4)
            keep[o.name[len(prefix):]] = o
        else:
            bpy.data.objects.remove(o)
    return keep


C.reset_scene()
suit = import_fbx(os.path.join(ROOT, "assets", "NinjaSim_HeroNinjas.fbx"), "HeroNinja_%s_" % TIER)


def build_spear():
    """Stand-in spear from primitives, in grip space (Roblox x, y, z -> Blender x, -z, y)."""
    parts = {}
    wood = C.material("SpearShaft", (0.42, 0.24, 0.12), roughness=0.6)
    steel = C.material("SpearHead", (0.85, 0.87, 0.9), metallic=0.9, roughness=0.25)
    gold = C.material("SpearBand", (0.85, 0.65, 0.2), metallic=0.8, roughness=0.3)
    red = C.material("SpearTassel", (0.8, 0.08, 0.08), roughness=0.8)

    def cyl(name, z0, z1, r, mat, verts=12):
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=abs(z1 - z0), location=(0, -(z0 + z1) / 2, 0), rotation=(math.pi / 2, 0, 0))
        o = bpy.context.object
        o.data.materials.append(mat)
        parts[name] = o
        return o

    head_base = -(SPEAR_TIP - SPEAR_HEAD)
    cyl("Shaft", SPEAR_BUTT, head_base, 0.12, wood)
    cyl("Butt", SPEAR_BUTT + 0.1, SPEAR_BUTT - 0.3, 0.15, gold)
    cyl("Collar", head_base + 0.45, head_base, 0.16, gold)
    cyl("Wrap", -1.1, -2.0, 0.14, red)
    # flat diamond blade: a 4-sided cone, squashed
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.3, radius2=0, depth=SPEAR_HEAD, location=(0, -(head_base - SPEAR_HEAD / 2), 0), rotation=(-math.pi / 2, 0, 0))
    o = bpy.context.object
    o.scale = (1, 1, 0.25)
    o.data.materials.append(steel)
    parts["Head"] = o
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.3, radius2=0.08, depth=0.5, location=(0, -(head_base + 0.65), 0), rotation=(math.pi / 2, 0, 0))
    o = bpy.context.object
    o.data.materials.append(red)
    parts["Tassel"] = o
    for o in parts.values():
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        o.select_set(False)
    return parts


if SPEAR:
    blade = build_spear()
else:
    blade = import_fbx(os.path.join(ROOT, "assets", "NinjaSim_HeroKatanas.fbx"), "HeroKatana_%s" % KATANA)
for name, o in list(suit.items()):
    if name.endswith("__Glow"):
        o["part"] = name[: -len("__Glow")]
    else:
        o["part"] = name
for o in blade.values():
    o["part"] = "Katana"
for o in list(suit.values()) + list(blade.values()):
    if "__Glow" in o.name or o.name.endswith("__Glow"):
        mat = bpy.data.materials.new(o.name + "_glow")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Emission Color"].default_value = (0.2, 0.8, 1, 1)
        bsdf.inputs["Emission Strength"].default_value = 3
        o.data.materials.clear()
        o.data.materials.append(mat)
actors = list(suit.values()) + list(blade.values())

floor_mat = C.material("Floor", (0.62, 0.64, 0.68), roughness=0.9)
bpy.ops.mesh.primitive_circle_add(vertices=64, radius=7, fill_type="NGON", location=(0, 0, 0))
floor = bpy.context.object
floor.data.materials.append(floor_mat)

trail_mat = bpy.data.materials.new("Trail")
trail_mat.use_nodes = True
tb = trail_mat.node_tree.nodes["Principled BSDF"]
tb.inputs["Base Color"].default_value = (1, 0.35, 0.1, 1)
tb.inputs["Emission Color"].default_value = (1, 0.45, 0.1, 1)
tb.inputs["Emission Strength"].default_value = 2.5


def pose(world):
    for o in actors:
        o.matrix_world = to_blender(world[o["part"]])


def trail(points, name):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 0.045
    sp = cu.splines.new("POLY")
    sp.points.add(len(points) - 1)
    for i, p in enumerate(points):
        b = P[:3, :3] @ np.asarray(p, dtype=float)
        sp.points[i].co = (float(b[0]), float(b[1]), float(b[2]), 1.0)
    ob = bpy.data.objects.new(name, cu)
    ob.data.materials.append(trail_mat)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def setup(size, samples):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.9, 0.9, 0.92, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    scene.world = world
    for i, (loc, e) in enumerate((((5, 7, 9), 1500), ((-7, 3, 5), 500), ((0, -8, 6), 700))):
        ld = bpy.data.lights.new("L%d" % i, "AREA")
        ld.energy = e
        ld.size = 6
        lo = bpy.data.objects.new("L%d" % i, ld)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 2.5)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(lo)
    cams = {}
    for name, loc, target, lens in (
        ("front", (6.5, 10.5, 4.6), (0, 0.5, 2.6), 30 if SPEAR else 42),  # character's front right, a little above
        ("top", (0, 0.5, 21), None, 40),  # straight down, the character's front at the top
        ("side", (17, 2, 3.4), (0, 2, 3.0), 30),  # from the character's right (spears: shows the reach)
    ):
        cd = bpy.data.cameras.new(name)
        cd.lens = lens
        cam = bpy.data.objects.new(name, cd)
        cam.location = loc
        if target:
            cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(cam)
        cams[name] = cam
    return cams


def render(path, cam):
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


os.makedirs(OUT, exist_ok=True)
from PIL import Image, ImageDraw  # noqa: E402

if "--gif" in flags:
    cams = setup((420, 420), 10)
    k = 0
    for move in data["moves"]:
        for f in move["frames"]:
            pose(solve_frame(f))
            render(os.path.join(OUT, "combo_%03d.png" % k), cams["front"])
            k += 1
    frames = [Image.open(os.path.join(OUT, "combo_%03d.png" % i)).convert("P", palette=Image.ADAPTIVE) for i in range(k)]
    frames[0].save(os.path.join(OUT, "combo.gif"), save_all=True, append_images=frames[1:], duration=int(1000 / data["fps"]), loop=0)
    print("GIF", k, "frames")
    sys.exit(0)

cams = setup((380, 380), 16)
VIEWS = ("front", "top", "side") if SPEAR else ("front", "top")
only = [int(a) for a in flag_value("--moves", ",".join(str(i) for i in range(1, len(data["moves"]) + 1))).split(",")]
for i, move in enumerate(data["moves"], 1):
    if i not in only:
        continue
    frames = move["frames"]
    # the blade tip's path while the move is in charge (sample frames.luau at 60 fps for a smooth line)
    tips = [tip_of(solve_frame(f))[0] for f in frames if f["weight"] > 0.5]
    print("TRAIL", [tuple(round(float(v), 1) for v in t) for t in tips[:4]])
    tr = trail(tips, "Trail%d" % i)
    # key moments: windup, mid strike, hit, follow-through
    picks = sorted({0, *[min(range(len(frames)), key=lambda j: abs(frames[j]["t"] - t)) for t in (
        move["trail"][0] * 0.8, move["trail"][0], (move["trail"][0] + move["hitAt"]) / 2, move["hitAt"], (move["hitAt"] + move["trail"][1]) / 2, move["trail"][1], 0.85)]})
    cells = []
    for j in picks:
        pose(solve_frame(frames[j]))
        row = []
        for view in VIEWS:
            p = os.path.join(OUT, "_m%d_%02d_%s.png" % (i, j, view))
            render(p, cams[view])
            row.append(Image.open(p).convert("RGB"))
        cells.append((frames[j]["t"], row))
    bpy.data.objects.remove(tr)
    W, H = 380, 380
    sheet = Image.new("RGB", (W * len(cells), H * len(VIEWS) + 30), (250, 250, 250))
    d = ImageDraw.Draw(sheet)
    for c, (t, row) in enumerate(cells):
        for r, img in enumerate(row):
            sheet.paste(img, (c * W, 30 + H * r))
        d.text((c * W + 8, 8), "t=%.2f%s" % (t, "  HIT" if abs(t - move["hitAt"]) < 0.04 else ""), fill=(0, 0, 0))
    d.text((W * len(cells) - 300, 8), "%d %s" % (i, move["name"]), fill=(0, 0, 0))
    sheet.save(os.path.join(OUT, "move%d.png" % i))
    for f in os.listdir(OUT):
        if f.startswith("_m%d_" % i):
            os.remove(os.path.join(OUT, f))
    print("SHEET", i, len(cells))
