"""Shared helpers for NinjaSim's Blender asset scripts (run with Blender's Python / `bpy`).

Conventions (so meshes drop straight into the game code):
  * 1 Blender unit = 1 Roblox stud.
  * Blender +Y maps to Roblox -Z (forward), Blender +Z maps to Roblox +Y (up), X stays X.
  * Every object is exported with its transforms applied, so a MeshPart's
    local axes match Roblox's world axes and its centre is its bounding-box centre.
  * write_manifest() records each object's bounding box in Roblox space so the
    game can place and scale the imported MeshParts exactly.
"""
import math
import bpy
import bmesh
from mathutils import Vector, Matrix


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, metallic=0.0, roughness=0.5, emission=None, strength=0.0, roblox="SmoothPlastic"):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat["roblox"] = roblox
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def mesh_object(name, verts, faces, mat=None, smooth=False, collection=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    (collection or bpy.context.scene.collection).objects.link(obj)
    if mat:
        obj.data.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    return obj


def recalc_normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()


def loft(rings, cap_start=True, cap_end=True):
    """Faces joining a list of equal-length closed rings (lists of vertex indices)."""
    faces = []
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            faces.append((a[i], a[j], b[j], b[i]))
    if cap_start:
        faces.append(tuple(reversed(rings[0])))
    if cap_end:
        faces.append(tuple(rings[-1]))
    return faces


def extrude_outline(name, outline, thickness, mat=None, axis="Y", bevel=0.0, collection=None):
    """Extrude a 2D outline (list of (u, v)) by `thickness` along `axis`, centred on 0."""
    verts, n = [], len(outline)
    for side in (-0.5, 0.5):
        for (u, v) in outline:
            w = side * thickness
            if axis == "Y":
                verts.append((u, w, v))
            elif axis == "X":
                verts.append((w, u, v))
            else:
                verts.append((u, v, w))
    bottom = list(range(n))
    top = list(range(n, 2 * n))
    faces = loft([bottom, top])
    obj = mesh_object(name, verts, faces, mat, collection=collection)
    recalc_normals(obj)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        apply_modifiers(obj)
    return obj


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        with bpy.context.temp_override(object=obj, active_object=obj):
            bpy.ops.object.modifier_apply(modifier=mod.name)


def shade_auto(obj, angle=35):
    for poly in obj.data.polygons:
        poly.use_smooth = True
    mod = obj.modifiers.new("Smooth", "SMOOTH_BY_ANGLE") if hasattr(bpy.types, "NodesModifier") and False else None
    # Blender 4.1+: mark sharp edges by angle so flat faces stay crisp after export
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(angle):
            e.smooth = False
    bm.to_mesh(obj.data)
    bm.free()


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


def lathe(name, profile, segments=24, mat=None, axis="Y", smooth=True, collection=None):
    """Revolve a profile [(radius, height)] around `axis` (bottom to top)."""
    verts, rings = [], []
    for (r, h) in profile:
        ring = []
        for s in range(segments):
            a = 2 * math.pi * s / segments
            x, y = r * math.cos(a), r * math.sin(a)
            if axis == "Y":
                verts.append((x, h, y))
            elif axis == "Z":
                verts.append((x, y, h))
            else:
                verts.append((h, x, y))
            ring.append(len(verts) - 1)
        rings.append(ring)
    faces = loft(rings)
    obj = mesh_object(name, verts, faces, mat, smooth=smooth, collection=collection)
    recalc_normals(obj)
    return obj


def to_roblox(v):
    """Blender vector -> Roblox (x, y, z)."""
    return (v.x, v.z, -v.y)


def bounds_roblox(obj):
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    rb = [to_roblox(p) for p in pts]
    lo = [min(p[i] for p in rb) for i in range(3)]
    hi = [max(p[i] for p in rb) for i in range(3)]
    center = [(lo[i] + hi[i]) / 2 for i in range(3)]
    size = [hi[i] - lo[i] for i in range(3)]
    return center, size


def roblox_style(obj):
    """(Color3 string, material name) from the object's first Blender material.
    A material may set custom props: mat["roblox"] = "Wood" etc."""
    if not obj.data.materials:
        return None, None
    mat = obj.data.materials[0]
    bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.use_nodes else None
    col = bsdf.inputs["Base Color"].default_value if bsdf else (0.8, 0.8, 0.8, 1)
    # linear -> sRGB for Color3
    def srgb(c):
        return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055
    rgb = tuple(max(0, min(255, round(srgb(col[i]) * 255))) for i in range(3))
    return "Color3.fromRGB(%d, %d, %d)" % rgb, mat.get("roblox", "SmoothPlastic")


def write_manifest(path, pack, objects, notes=""):
    """Lua table: name -> { Center, Size, Tris, Color, Material } in Roblox space."""
    lines = ["-- Generated by tools/blender (" + pack + "). Do not edit by hand.", notes and ("-- " + notes) or "", "return {"]
    for obj in sorted(objects, key=lambda o: o.name):
        c, s = bounds_roblox(obj)
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        color, mat = roblox_style(obj)
        extra = (', Color = %s, Material = Enum.Material.%s' % (color, mat)) if color else ""
        lines.append(
            '\t["%s"] = { Center = Vector3.new(%.4f, %.4f, %.4f), Size = Vector3.new(%.4f, %.4f, %.4f), Tris = %d%s },'
            % (obj.name, c[0], c[1], c[2], max(s[0], 0.01), max(s[1], 0.01), max(s[2], 0.01), tris, extra)
        )
    lines.append("}")
    with open(path, "w") as f:
        f.write("\n".join(l for l in lines if l is not None) + "\n")


def export_fbx(path, objects, embed=False):
    """embed=True copies image textures into the FBX (the UI icon atlas needs this)."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z", axis_up="Y", object_types={"MESH"}, use_mesh_modifiers=True,
        mesh_smooth_type="FACE", bake_space_transform=True, add_leaf_bones=False, bake_anim=False,
        path_mode="COPY" if embed else "STRIP", embed_textures=embed,
    )


def apply_transforms(objs):
    bpy.context.view_layer.update()  # matrix_world is stale right after setting location/scale
    for o in objs:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)


def render_preview(path, objects, size=(900, 600), camera_dir=(1.0, -1.6, 0.9), margin=1.25, samples=24, background=(0.32, 0.34, 0.4), ortho=False):
    """Cycles CPU render of the given objects, framed automatically."""
    bpy.context.view_layer.update()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (*background, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scene.world = world
    pts = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    center = (lo + hi) / 2
    radius = (hi - lo).length / 2
    d = Vector(camera_dir).normalized()
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    if ortho:
        cam_data.type = "ORTHO"
        aspect = size[0] / size[1]
        extent = hi - lo
        # widest visible extent across the image plane (camera looks along -camera_dir)
        side = Vector((0, 0, 1)).cross(d)
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side.normalize()
        up = d.cross(side).normalized()
        w = sum(abs(side[i]) * extent[i] for i in range(3))
        h = sum(abs(up[i]) * extent[i] for i in range(3))
        cam_data.ortho_scale = max(w, h * aspect) * margin
    dist = radius * margin / math.tan(cam_data.angle / 2)
    cam.location = center + d * dist
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    for i, (loc, energy) in enumerate([((1, -1, 2), 900), ((-2, -1, 1), 350), ((0, 2, 1.5), 500)]):
        ld = bpy.data.lights.new("L%d" % i, "AREA")
        ld.energy = energy * max(radius, 0.5) ** 2
        ld.size = radius * 2
        lo_ = bpy.data.objects.new("L%d" % i, ld)
        lo_.location = center + Vector(loc) * radius * 3
        lo_.rotation_euler = (center - lo_.location).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(lo_)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def rgb(r, g, b):
    """sRGB 0-255 -> linear 0-1 (what Blender materials expect)."""
    def lin(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b))


def box(name, size, center, mat=None, bevel=0.0, collection=None):
    sx, sy, sz = size
    cx, cy, cz = center
    v = [(cx + dx * sx / 2, cy + dy * sy / 2, cz + dz * sz / 2) for dx in (-1, 1) for dy in (-1, 1) for dz in (-1, 1)]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    o = mesh_object(name, v, f, mat, collection=collection)
    recalc_normals(o)
    if bevel > 0:
        m = o.modifiers.new("Bevel", "BEVEL")
        m.width = bevel
        m.segments = 2
        apply_modifiers(o)
    return o


def cylinder(name, radius, height, base, mat=None, segments=16, radius_top=None, axis="Z"):
    """Vertical cylinder (Blender Z) standing on `base` = (x, y, z)."""
    rt = radius if radius_top is None else radius_top
    o = lathe(name, [(0.0, 0.0), (radius, 0.0), (rt, height), (0.0, height)], segments, mat, axis="Z")
    o.location = base
    apply_transforms([o])
    return o


def blob(name, radius, center, mat=None, subdiv=2, noise=0.25, seed=1, squash=1.0):
    """Low-poly lumpy sphere (foliage, rocks, bushes)."""
    import random
    rnd = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=center)
    o = bpy.context.active_object
    o.name = name
    for v in o.data.vertices:
        k = 1 + rnd.uniform(-noise, noise)
        v.co = Vector((v.co.x * k, v.co.y * k, v.co.z * k * squash))
    if mat:
        o.data.materials.append(mat)
    apply_transforms([o])
    return o


def merge(objs, name, mat=None):
    apply_transforms(objs)
    o = join(objs, name)
    if mat is not None:
        o.data.materials.clear()
        o.data.materials.append(mat)
    return o
