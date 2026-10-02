"""Renders views of one zone from the playtest's world dump.

    SCENARIO=worldshots WORLDSHOTS_ZONE=village lune run run.luau     (in tools/playtest)
    python3 tools/blender/world_preview.py /tmp/claude-0/worldshots/village.json assets/previews/world [view ...]

The land is the height field from shared/Landscape (grass, road and cliff colours from
the zone theme, pond water at its level); every visible part the WorldBuilder and
ZoneDecor built is drawn, merged into one mesh per colour and material so thousands of
parts render quickly. Terrain carved by scenery (the village canal) isn't in the height
field, and particles and lights are left out. Views: overview, spawn, street, torii,
temples, pavilion (default: all).
"""
import json
import math
import os
import sys

import bpy  # noqa: I001 (bpy must load before bmesh)
import bmesh
from mathutils import Matrix, Vector

# Roblox (x, y, z) with y up and -z forward -> Blender (x, -z, y) with z up
P = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def rbx(v):
    return Vector((v[0], -v[2], v[1]))


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras):
        for item in list(coll):
            coll.remove(item)


_mats = {}


def material(color, kind, alpha=1.0):
    key = (tuple(round(c, 2) for c in color), kind, round(alpha, 1))
    if key in _mats:
        return _mats[key]
    mat = bpy.data.materials.new("M%d" % len(_mats))
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    lin = [c ** 2.2 for c in color]
    bsdf.inputs["Base Color"].default_value = (*lin, 1)
    bsdf.inputs["Roughness"].default_value = 0.7
    if kind == "Neon":
        bsdf.inputs["Emission Color"].default_value = (*lin, 1)
        bsdf.inputs["Emission Strength"].default_value = 3.0
    elif kind in ("Foil", "Metal"):
        bsdf.inputs["Metallic"].default_value = 0.7
        bsdf.inputs["Roughness"].default_value = 0.3
    elif kind in ("Glass", "Ice", "Water"):
        bsdf.inputs["Roughness"].default_value = 0.05
        bsdf.inputs["Transmission Weight"].default_value = 0.5
    bsdf.inputs["Alpha"].default_value = alpha
    _mats[key] = mat
    return mat


# unit primitives (Roblox local space, size 1)
def prim_verts(kind):
    if kind == "Ball":
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.5)
    elif kind == "Cylinder":
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.5, radius2=0.5, depth=1,
                              matrix=Matrix.Rotation(math.pi / 2, 4, "Y"))
    elif kind == "Wedge":
        bm = bmesh.new()
        h = 0.5
        vs = [bm.verts.new(v) for v in ((-h, -h, -h), (h, -h, -h), (h, -h, h), (-h, -h, h), (-h, h, h), (h, h, h))]
        for f in ((0, 1, 2, 3), (3, 2, 5, 4), (0, 4, 5, 1), (0, 3, 4), (1, 5, 2)):
            bm.faces.new([vs[i] for i in f])
    else:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
    bm.verts.index_update()
    verts = [tuple(v.co) for v in bm.verts]
    faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return verts, faces


PRIMS = {k: prim_verts(k) for k in ("Ball", "Cylinder", "Wedge", "Block")}


def add_parts(parts):
    buckets = {}
    for part in parts:
        kind = "Wedge" if part["class"] == "WedgePart" else (part.get("shape") or "Block")
        if kind not in PRIMS:
            kind = "Block"
        sx, sy, sz = part["size"]
        if kind == "Ball":
            d = min(sx, sy, sz)
            sx = sy = sz = d
        elif kind == "Cylinder":
            d = min(sy, sz)
            sy = sz = d
        x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part["cf"]
        m = P @ Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0, 0, 0, 1))) @ Matrix.Diagonal((sx, sy, sz, 1))
        alpha = 1 - part["transparency"]
        key = (tuple(round(c, 2) for c in part["color"]), part["material"], round(alpha, 1))
        b = buckets.setdefault(key, ([], []))
        verts, faces = PRIMS[kind]
        base = len(b[0])
        b[0].extend(tuple(m @ Vector(v)) for v in verts)
        b[1].extend(tuple(i + base for i in f) for f in faces)
    for i, (key, (verts, faces)) in enumerate(buckets.items()):
        mesh = bpy.data.meshes.new("parts%d" % i)
        mesh.from_pydata(verts, [], faces)
        mesh.validate()
        mesh.materials.append(material(key[0], key[1], key[2]))
        obj = bpy.data.objects.new("parts%d" % i, mesh)
        bpy.context.scene.collection.objects.link(obj)


def add_land(data):
    rows, step = data["rows"], data["step"]
    cx, cy, cz = data["center"]
    H, D = data["h"], data["d"]
    theme = data["theme"]
    verts, faces, colors = [], [], []
    nz, nx = len(rows), len(rows[0])
    for j, row in enumerate(rows):
        for i, (h, road, s, wl) in enumerate(row):
            verts.append(tuple(rbx((cx - H + i * step, cy + h, cz - D + j * step))))
    for j in range(nz - 1):
        for i in range(nx - 1):
            a = j * nx + i
            faces.append((a, a + 1, a + nx + 1, a + nx))
            h, road, s, wl = rows[j][i]
            hs = [rows[j][i][0], rows[j][i + 1][0], rows[j + 1][i][0], rows[j + 1][i + 1][0]]
            slope = (max(hs) - min(hs)) / step
            if road > 0.5:
                c = theme["path"]
            elif slope > 1.0 or (s > 0 and slope > 0.6):
                c = theme["rock"]
            else:
                c = theme["ground"]
            colors.append(c)
    mesh = bpy.data.meshes.new("Land")
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    keys = {}
    for c in colors:
        k = tuple(round(x, 2) for x in c)
        if k not in keys:
            keys[k] = len(keys)
            mesh.materials.append(material(c, "Grass"))
    for poly, c in zip(mesh.polygons, colors):
        poly.material_index = keys[tuple(round(x, 2) for x in c)]
    obj = bpy.data.objects.new("Land", mesh)
    bpy.context.scene.collection.objects.link(obj)
    # pond water: one quad per wet cell at its level
    wv, wf = [], []
    for j in range(nz - 1):
        for i in range(nx - 1):
            wl = rows[j][i][3]
            if wl is not False and wl is not None:
                x0, z0 = cx - H + i * step, cz - D + j * step
                base = len(wv)
                for dx, dz in ((0, 0), (step, 0), (step, step), (0, step)):
                    wv.append(tuple(rbx((x0 + dx, cy + wl, z0 + dz))))
                wf.append((base, base + 1, base + 2, base + 3))
    if wv:
        wm = bpy.data.meshes.new("Water")
        wm.from_pydata(wv, [], wf)
        wm.validate()
        wm.materials.append(material((0.25, 0.5, 0.62), "Water", 0.85))
        wo = bpy.data.objects.new("Water", wm)
        bpy.context.scene.collection.objects.link(wo)


def setup(size, samples):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.get("W") or bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.55, 0.68, 0.85, 1)
    bg.inputs[1].default_value = 0.9
    scene.world = world
    ld = bpy.data.lights.new("Sun", "SUN")
    ld.energy = 3.2
    ld.angle = math.radians(8)
    sun = bpy.data.objects.new("Sun", ld)
    sun.rotation_euler = rbx((0.45, -1, 0.3)).normalized().to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(sun)


def shoot(eye, target, fov, path):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.angle = math.radians(fov)
    cam_data.clip_end = 3000
    cam = bpy.data.objects.new("Cam", cam_data)
    e, t = rbx(eye), rbx(target)
    cam.location = e
    cam.rotation_euler = (t - e).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    print("wrote", path)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    data = json.load(open(args[0]))
    out = args[1]
    wanted = set(args[2:])
    os.makedirs(out, exist_ok=True)
    clear()
    setup((1280, 720), 24)
    add_land(data)
    add_parts(data["parts"])
    cx, cy, cz = data["center"]
    sx, sy, sz = data["spawn"]
    bx, bz = data["boss"]

    def g(x, y, z):
        return (cx + x, cy + y, cz + z)

    views = {
        "overview": (g(-40, 260, 330), g(-10, 0, 0), 55),
        "spawn": ((sx - 22, sy + 9, sz + 6), (sx + 70, sy + 4, sz), 62),
        "street": ((sx + 46, sy + 7, sz + 2), (sx + 140, sy + 2, sz - 4), 58),
        "torii": (g(70, 22, -14), g(bx - 20, 20, bz - 20), 55),
        "temples": (g(-70, 45, -40), g(-10, 20, -180), 55),
        "pavilion": (g(-160, 22, 70), g(-160, 6, 150), 55),
    }
    for name, (eye, target, fov) in views.items():
        if wanted and name not in wanted:
            continue
        shoot(eye, target, fov, os.path.join(out, "%s_%s.png" % (data["zone"], name)))


main()
