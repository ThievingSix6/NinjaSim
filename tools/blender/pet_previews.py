"""Renders pets and their mutations from the playtest's part dump.

    SCENARIO=petshots lune run run.luau          (in tools/playtest; writes /tmp/claude-0/petshots/pets.json)
    python3 tools/blender/pet_previews.py /tmp/claude-0/petshots/pets.json assets/previews/pets/mutations [--ui DIR]

Writes one sheet per pet (<pet>_mutations.png): the plain pet and every mutation,
all with the same camera and standing on the same floor, so Big and Giant read at
their real size. With --ui DIR it also renders each model the way Kit.Viewport frames
it in a card (transparent PNGs) plus DIR/assets.json for tools/uipreview, so the UI
previews show the pets instead of placeholders.

The parts come from the real PetBuilder/MutationLook code, so what you see is what the
game builds. Particles are drawn as a scatter of small glowing dots, beams as zigzag
tubes and Roblox materials are approximated (Neon glows, Foil is shiny gold metal,
Ice and Glass are see-through, ForceField is a faint glowing shell).
"""
import json
import math
import os
import random
import sys

import bpy  # noqa: I001 (bpy must load before bmesh)
import bmesh
from mathutils import Matrix, Vector

FONT = os.path.join(os.path.dirname(__file__), "..", "uipreview", "fonts", "FredokaOne-400.woff2")

# Roblox (x, y, z) with y up and -z forward -> Blender (x, -z, y) with z up
P = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def rbx_vec(v):
    return Vector((v[0], -v[2], v[1]))


_materials = {}


def clear_scene():
    _materials.clear()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras, bpy.data.curves):
        for item in list(coll):
            coll.remove(item)




def material(color, kind, alpha):
    key = (tuple(round(c, 3) for c in color), kind, round(alpha, 2))
    if key in _materials:
        return _materials[key]
    mat = bpy.data.materials.new("M%d" % len(_materials))
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    lin = [c ** 2.2 for c in color]
    bsdf.inputs["Base Color"].default_value = (*lin, 1)
    bsdf.inputs["Roughness"].default_value = 0.5
    if kind == "Neon":
        bsdf.inputs["Emission Color"].default_value = (*lin, 1)
        bsdf.inputs["Emission Strength"].default_value = 4.0
    elif kind == "Foil":
        bsdf.inputs["Metallic"].default_value = 0.65
        bsdf.inputs["Roughness"].default_value = 0.3
    elif kind == "Metal":
        bsdf.inputs["Metallic"].default_value = 0.8
        bsdf.inputs["Roughness"].default_value = 0.35
    elif kind in ("Ice", "Glass"):
        bsdf.inputs["Roughness"].default_value = 0.08
        bsdf.inputs["Transmission Weight"].default_value = 0.35
        bsdf.inputs["Coat Weight"].default_value = 0.6
    elif kind == "ForceField":
        bsdf.inputs["Emission Color"].default_value = (*lin, 1)
        bsdf.inputs["Emission Strength"].default_value = 0.9
        alpha = min(alpha, 0.16)
    elif kind in ("Fabric", "Wood"):
        bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Alpha"].default_value = alpha
    _materials[key] = mat
    return mat


def part_mesh(part):
    """Mesh for one Roblox part, in Roblox local space."""
    bm = bmesh.new()
    sx, sy, sz = part["size"]
    shape = part.get("shape") or "Block"
    if part["class"] == "WedgePart":
        hx, hy, hz = sx / 2, sy / 2, sz / 2
        # sloped face looks forward (-z) and up; the tall side is at +z
        vs = [bm.verts.new(v) for v in ((-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz), (-hx, hy, hz), (hx, hy, hz))]
        for f in ((0, 1, 2, 3), (3, 2, 5, 4), (0, 4, 5, 1), (0, 3, 4), (1, 5, 2)):
            bm.faces.new([vs[i] for i in f])
    elif shape == "Ball":
        d = min(sx, sy, sz)
        bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=d / 2)
    elif shape == "Cylinder":
        d = min(sy, sz)
        bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=d / 2, radius2=d / 2, depth=sx,
                              matrix=Matrix.Rotation(math.pi / 2, 4, "Y"))
    else:
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((sx, sy, sz, 1)))
    for f in bm.faces:
        f.smooth = shape in ("Ball", "Cylinder")
    mesh = bpy.data.meshes.new(part["name"])
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def cframe_matrix(cf, offset=(0, 0, 0)):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf
    m = Matrix(((r00, r01, r02, x + offset[0]), (r10, r11, r12, y + offset[1]), (r20, r21, r22, z + offset[2]), (0, 0, 0, 1)))
    return P @ m


def rbx_bounds(model, rotation=None):
    """Axis-aligned bounds (Roblox space) of the model's parts, optionally turned about Y."""
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for part in model["parts"]:
        cf = part["cf"]
        pos = Vector(cf[0:3])
        rot = Matrix((cf[3:6], cf[6:9], cf[9:12]))
        if rotation is not None:
            pos = rotation @ pos
            rot = rotation @ rot
        half = Vector(part["size"]) / 2
        for i in range(3):
            ext = sum(abs(rot[i][j]) * half[j] for j in range(3))
            lo[i] = min(lo[i], pos[i] - ext)
            hi[i] = max(hi[i], pos[i] + ext)
    return Vector(lo), Vector(hi)


def build(model, offset=(0, 0, 0), turn=0.0, seed=1):
    """Adds the model to the scene. `turn` spins it about Roblox Y (radians)."""
    rng = random.Random(seed)
    turn_m = Matrix.Rotation(turn, 4, "Z")  # Roblox Y is Blender Z
    objs = []
    for part in model["parts"]:
        if part["transparency"] >= 0.99:
            continue
        mesh = part_mesh(part)
        mesh.materials.append(material(part["color"], part["material"], 1 - part["transparency"]))
        obj = bpy.data.objects.new(part["name"], mesh)
        obj.matrix_world = Matrix.Translation(rbx_vec(offset)) @ turn_m @ cframe_matrix(part["cf"])
        bpy.context.scene.collection.objects.link(obj)
        objs.append(obj)
    lo, hi = rbx_bounds(model)
    extent = (hi - lo).length / 2
    center = (lo + hi) / 2
    for fx in model["fx"]:
        if fx["kind"] == "particles":
            count = int(min(36, fx["rate"] * 1.6))
            smoky = fx["emission"] < 0.5
            for i in range(count):
                k = i / max(1, count - 1)
                c = [a + (b - a) * k for a, b in zip(fx["colors"][0], fx["colors"][1])]
                d = Vector((rng.uniform(-1, 1), rng.uniform(-0.7, 1.1), rng.uniform(-1, 1)))
                pos = center + Vector((d.x * (hi - lo).x, d.y * (hi - lo).y, d.z * (hi - lo).z)) * 0.62
                bm = bmesh.new()
                r = fx["size"] * (0.28 if smoky else 0.22) * rng.uniform(0.5, 1.0)
                bmesh.ops.create_icosphere(bm, subdivisions=1 if not smoky else 2, radius=max(r, 0.03))
                mesh = bpy.data.meshes.new("fx")
                bm.to_mesh(mesh)
                bm.free()
                mesh.materials.append(material(c, "ForceField" if smoky else "Neon", 0.35 if smoky else 1))
                obj = bpy.data.objects.new("fx", mesh)
                obj.matrix_world = Matrix.Translation(rbx_vec(offset)) @ turn_m @ Matrix.Translation(rbx_vec(pos))
                bpy.context.scene.collection.objects.link(obj)
        elif fx["kind"] == "beam":
            a, b = Vector(fx["a"]), Vector(fx["b"])
            curve = bpy.data.curves.new("arc", "CURVE")
            curve.dimensions = "3D"
            curve.bevel_depth = max(fx["width"] * 0.35, 0.02)
            spline = curve.splines.new("POLY")
            n = 7
            spline.points.add(n - 1)
            for i in range(n):
                t = i / (n - 1)
                p = a.lerp(b, t)
                if 0 < i < n - 1:
                    p += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 0.25 * (a - b).length / 2
                q = rbx_vec(p)
                spline.points[i].co = (q.x, q.y, q.z, 1)
            curve.materials.append(material(fx["color"], "Neon", 1))
            obj = bpy.data.objects.new("arc", curve)
            obj.matrix_world = Matrix.Translation(rbx_vec(offset)) @ turn_m
            bpy.context.scene.collection.objects.link(obj)
        elif fx["kind"] == "light":
            ld = bpy.data.lights.new("pl", "POINT")
            ld.color = fx["color"]
            ld.energy = 25 * fx["brightness"] * max(extent, 0.6) ** 2
            ld.shadow_soft_size = 0.3
            obj = bpy.data.objects.new("pl", ld)
            obj.matrix_world = Matrix.Translation(rbx_vec(offset)) @ turn_m @ Matrix.Translation(rbx_vec(fx["at"]))
            bpy.context.scene.collection.objects.link(obj)
    return objs


def setup_render(size, transparent, samples=40):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = transparent
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.get("W") or bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.62, 0.66, 0.74, 1) if not transparent else (0.8, 0.8, 0.84, 1)
    bg.inputs[1].default_value = 0.75
    scene.world = world


def camera(eye, target, fov_deg):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.angle = math.radians(fov_deg)
    cam_data.sensor_fit = "VERTICAL"
    cam_data.clip_end = 1000
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = eye
    cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam


def sun(direction_rbx, energy):
    ld = bpy.data.lights.new("Sun", "SUN")
    ld.energy = energy
    ld.angle = math.radians(12)
    obj = bpy.data.objects.new("Sun", ld)
    d = rbx_vec(direction_rbx).normalized()
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(obj)


def floor(z, size):
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size)
    mesh = bpy.data.meshes.new("Floor")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material((0.42, 0.6, 0.36), "SmoothPlastic", 1))
    obj = bpy.data.objects.new("Floor", mesh)
    obj.location = (0, 0, z)
    bpy.context.scene.collection.objects.link(obj)


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def sheet(pet, variants, mutations, out_dir, tile=360):
    """One tile per variant, same camera for all, every model standing on the floor."""
    from PIL import Image, ImageDraw, ImageFont

    # frame for the biggest variant
    big_lo, big_hi = None, None
    for v in variants:
        lo, hi = rbx_bounds(v["model"])
        size = hi - lo
        if big_lo is None or size.length > (big_hi - big_lo).length:
            big_lo, big_hi = lo - Vector((0, lo.y, 0)), hi - Vector((0, lo.y, 0))
    radius = (big_hi - big_lo).length / 2
    target_rbx = Vector((0, (big_hi.y - big_lo.y) * 0.42, 0))
    eye_rbx = target_rbx + Vector((0.62, 0.42, -0.95)).normalized() * radius / math.tan(math.radians(14)) * 1.02
    tiles = []
    for i, v in enumerate(variants):
        clear_scene()
        setup_render((tile, tile), False, samples=48)
        lo, _ = rbx_bounds(v["model"])
        build(v["model"], offset=(0, -lo.y, 0), seed=i + 3)
        floor(0, 60)
        sun((-0.6, -1.0, 0.5), 3.2)
        camera(rbx_vec(eye_rbx), rbx_vec(target_rbx), 28)
        path = os.path.join(out_dir, "_tile_%s_%d.png" % (pet, i))
        render(path)
        tiles.append(path)
    cols = 3
    rows = math.ceil(len(tiles) / cols)
    label_h = 46
    img = Image.new("RGB", (cols * tile, rows * (tile + label_h)), (32, 40, 56))
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, 22)
    small = ImageFont.truetype(FONT, 15)
    by_id = {m["id"]: m for m in mutations}
    for i, path in enumerate(tiles):
        x, y = (i % cols) * tile, (i // cols) * (tile + label_h)
        img.paste(Image.open(path).convert("RGB"), (x, y))
        os.remove(path)
        m = by_id.get(variants[i]["mutation"])
        title = (m["name"] + " " if m else "") + pet.replace("_", " ").title()
        sub = ("x%g stats  -  1 in %s" % (m["mult"], format(m["oneIn"], ","))) if m else "no mutation"
        color = tuple(int(c * 255) for c in m["color"]) if m else (235, 235, 245)
        draw.text((x + 10, y + tile + 2), title, font=font, fill=color, stroke_width=2, stroke_fill=(20, 16, 30))
        draw.text((x + 10, y + tile + 26), sub, font=small, fill=(206, 216, 236))
    out = os.path.join(out_dir, "%s_mutations.png" % pet)
    img.save(out)
    print("wrote", out)


def ui_zoom(base, mutation):
    """Common.PetZoom: bigger mutations sit closer in the card."""
    if mutation and mutation["scale"] > 1:
        return base / (1 + (mutation["scale"] - 1) * 0.35)
    return base


def ui_render(name, model, zoom, out_dir, size=256):
    """The model as Kit.Viewport frames it in a card: FOV 30, 35 degrees round, ViewRotation applied."""
    clear_scene()
    setup_render((size, size), True, samples=32)
    turn = model.get("viewTurn", 0.0)
    rot = Matrix.Rotation(turn, 3, "Y")
    lo, hi = rbx_bounds(model, rot)
    radius = (hi - lo).length / 2
    distance = radius / math.tan(math.radians(15)) * zoom
    center = (lo + hi) / 2
    a = math.radians(35)
    eye = center + Vector((math.sin(a) * distance, radius * 0.35, math.cos(a) * distance))
    build(model, turn=turn)
    sun((-1, -1.2, -0.8), 3.0)
    camera(rbx_vec(eye), rbx_vec(center), 30)
    path = os.path.join(out_dir, name + ".png")
    render(path)
    return path


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    src, out_dir = args[0], args[1]
    ui_dir = args[args.index("--ui") + 1] if "--ui" in args else None
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    os.makedirs(out_dir, exist_ok=True)
    data = json.load(open(src))
    mutations = data["mutations"]
    for pet in data["pets"]:
        if only and pet not in only:
            continue
        sheet(pet, data["models"][pet], mutations, out_dir)
    if ui_dir:
        os.makedirs(ui_dir, exist_ok=True)
        by_id = {m["id"]: m for m in mutations}
        assets = {}
        icons = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "icons", "UIIcons.png"))
        assets["rbxassetid://1000001"] = {"file": icons, "w": 1024, "h": 1024}
        for pet, variants in data["models"].items():
            for v in variants:
                m = by_id.get(v["mutation"])
                name = pet + ("_" + m["id"] if m else "")
                v["model"]["viewTurn"] = math.pi if data.get("viewTurn", True) else 0.0
                path = ui_render(name, v["model"], ui_zoom(1.15, m and dict(m, scale=v["model"]["scale"])), ui_dir)
                assets["model:" + name] = {"file": os.path.abspath(path), "w": 256, "h": 256}
        json.dump(assets, open(os.path.join(ui_dir, "assets.json"), "w"), indent=1)
        print("wrote", os.path.join(ui_dir, "assets.json"))


main()
