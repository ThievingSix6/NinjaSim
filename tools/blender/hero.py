"""Mesh helpers and the studio preview renderer for the textured "hero" models
(hero_katanas.py, hero_ninjas.py). Everything is built from explicit vertex lists
and bmesh so shapes stay crisp and low-poly; bake.py then paints colour + AO.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C


def flat(name, verts, faces, mat):
    o = C.mesh_object(name, verts, faces, mat)
    C.recalc_normals(o)
    return o


def smooth(o, angle=40):
    C.shade_auto(o, angle)
    return o


def tray(name, size, center, mat, rim=0.035, depth=0.05, bevel=0.012, open_top=True, open_bottom=False):
    """Box with a recessed top (and/or bottom): the 'hollow box' guards and pommels."""
    sx, sy, sz = size
    o = C.box(name, size, center, mat)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    for want, sign in ((open_top, 1), (open_bottom, -1)):
        if not want:
            continue
        cap = [f for f in bm.faces if f.normal.y * sign > 0.9]
        bmesh.ops.inset_region(bm, faces=cap, thickness=rim, depth=0)
        bmesh.ops.translate(bm, verts=list({v for f in cap for v in f.verts}), vec=(0, -sign * depth, 0))
    bm.to_mesh(o.data)
    bm.free()
    if bevel > 0:
        m = o.modifiers.new("Bevel", "BEVEL")
        m.width = bevel
        m.segments = 1
        m.limit_method = "ANGLE"
        C.apply_modifiers(o)
    return o


def rect_band(name, half_x, half_z, y0, turns, pitch, width, thick, mat, phase=0.0, hand=1, gap=0.002):  # noqa: C901
    """A flat ribbon wound around a rectangular core (half extents half_x, half_z)
    starting at height y0; `hand` = +1/-1 picks the winding direction. Sampled only
    at the corners, so each side is one flat, crisp strip like a leather wrap."""
    P = 2 * (2 * half_x + 2 * half_z)  # perimeter
    corners = [(half_x, half_z), (-half_x, half_z), (-half_x, -half_z), (half_x, -half_z)]
    if hand < 0:
        corners = [(x, -z) for x, z in corners]
    total = turns * P
    def at(d):
        d = d % P
        acc = 0.0
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            L = math.dist(a, b)
            if d <= acc + L + 1e-9:
                t = (d - acc) / L
                return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), i
            acc += L
        return corners[0], 0
    cum = [0.0]
    for i in range(4):
        cum.append(cum[-1] + math.dist(corners[i], corners[(i + 1) % 4]))
    marks = [phase * P]
    k = 0
    while True:
        for c in cum[:4]:
            d = c + k * P
            if phase * P < d < phase * P + total:
                marks.append(d)
        k += 1
        if k * P > phase * P + total:
            break
    marks.append(phase * P + total)
    marks.sort()
    verts, faces = [], []
    for d in marks:
        (x, z), _ = at(d)
        # outward direction at this point (corners get the diagonal)
        nx = (1 if x >= half_x - 1e-6 else -1 if x <= -half_x + 1e-6 else 0)
        nz = (1 if z >= half_z - 1e-6 else -1 if z <= -half_z + 1e-6 else 0)
        y = y0 + (d - phase * P) / P * pitch
        for (off, dy) in ((gap, -width / 2), (gap, width / 2), (gap + thick, width / 2), (gap + thick, -width / 2)):
            verts.append((x + nx * off, y + dy, z + nz * off))
    n = len(marks)
    for i in range(n - 1):
        a, b = i * 4, (i + 1) * 4
        for j in range(4):
            faces.append((a + j, a + (j + 1) % 4, b + (j + 1) % 4, b + j))
    faces.append((0, 3, 2, 1))
    faces.append(((n - 1) * 4, (n - 1) * 4 + 1, (n - 1) * 4 + 2, (n - 1) * 4 + 3))
    return flat(name, verts, faces, mat)


def mirror_x(o, name):
    """Mirrored copy across X (keeps the UVs, so it shares the baked texture)."""
    c = o.copy()
    c.data = o.data.copy()
    c.name = name
    c.data.name = name
    bpy.context.scene.collection.objects.link(c)
    c.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
    c.data.flip_normals()
    c.data.update()
    return c


def studio_render(path, objects, view=(1, 0, 0), up=(0, 0, 1), size=(800, 1600), margin=1.08, samples=64,
                  background=(0.93, 0.93, 0.94), ortho=True, key=(1.0, -0.6, 1.4), hide_others=True):
    """Soft studio render like justin's reference sheets: orthographic, three area lights."""
    scene = bpy.context.scene
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = hide_others and o not in objects
    for o in [o for o in bpy.data.objects if o.type in ("CAMERA", "LIGHT")]:
        bpy.data.objects.remove(o)
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.get("Studio") or bpy.data.worlds.new("Studio")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (*background, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
    world.light_settings.distance = 0.25
    scene.world = world
    pts = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    center = (lo + hi) / 2
    radius = (hi - lo).length / 2
    d = Vector(view).normalized()
    u = Vector(up)
    u = (u - d * u.dot(d)).normalized()
    x = u.cross(d).normalized()
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    ext = hi - lo
    w = sum(abs(x[i]) * ext[i] for i in range(3))
    h = sum(abs(u[i]) * ext[i] for i in range(3))
    aspect = size[0] / size[1]
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = max(w, h * aspect) * margin if aspect >= 1 else max(w / aspect, h) * margin
    else:
        cam_data.lens = 85
    dist = radius * 4 if ortho else radius * margin / math.tan(cam_data.angle / 2) * 1.1
    cam.matrix_world = Matrix.Translation(center + d * dist) @ Matrix((
        (x[0], u[0], d[0], 0), (x[1], u[1], d[1], 0), (x[2], u[2], d[2], 0), (0, 0, 0, 1))).to_4x4()
    cam_data.clip_end = dist * 4
    scene.camera = cam
    kx = Vector(key)
    rig = [(d * kx.x + x * kx.y + u * kx.z, 1.3), (d * 1.0 - x * 1.2 + u * 0.2, 0.45), (-d * 1.0 + u * 1.2 + x * 0.6, 0.6)]
    for i, (loc, energy) in enumerate(rig):
        ld = bpy.data.lights.new("L%d" % i, "AREA")
        ld.energy = energy * 120 * max(radius, 0.5) ** 2
        ld.size = radius * 2.5
        lo_ = bpy.data.objects.new("L%d" % i, ld)
        lo_.location = center + loc.normalized() * radius * 3
        lo_.rotation_euler = (center - lo_.location).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(lo_)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def paint(name, color, noise=0.0, scale=30.0, streaks=0.0, roughness=0.6, emission=0.0, roblox="SmoothPlastic"):
    """Principled material whose base colour is `color` (sRGB 0-255) broken up with a
    little noise (fabric/leather grain) and fine dark streaks (worn cloth), for baking."""
    mat = C.material(name, C.rgb(*color), roughness=roughness, roblox=roblox)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    base = Vector(C.rgb(*color))
    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = (*base, 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    if noise <= 0 and streaks <= 0:
        return mat
    tex = nt.nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = scale
    tex.inputs["Detail"].default_value = 6
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[0].color = (*(base * (1 - noise)), 1)
    ramp.color_ramp.elements[1].color = (*(base * (1 + noise * 0.6)), 1)
    nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
    out = ramp.outputs["Color"]
    if streaks > 0:
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.wave_type = "BANDS"
        wave.inputs["Scale"].default_value = scale * 1.4
        wave.inputs["Distortion"].default_value = 30
        wave.inputs["Detail"].default_value = 4
        mask = nt.nodes.new("ShaderNodeValToRGB")
        mask.color_ramp.elements[0].position = 0.0
        mask.color_ramp.elements[1].position = 0.04
        mask.color_ramp.elements[0].color = (1 - streaks, 1 - streaks, 1 - streaks, 1)
        mask.color_ramp.elements[1].color = (1, 1, 1, 1)
        nt.links.new(wave.outputs["Fac"], mask.inputs["Fac"])
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(out, mul.inputs["A"])
        nt.links.new(mask.outputs["Color"], mul.inputs["B"])
        out = mul.outputs["Result"]
    nt.links.new(out, bsdf.inputs["Base Color"])
    return mat


# ---------------------------------------------------------------- decals
def ensure_uv(o):
    """The atlas UV map must stay the first layer (Roblox reads UV channel 0)."""
    if "UVMap" not in o.data.uv_layers:
        o.data.uv_layers.new(name="UVMap")
    o.data.uv_layers.active = o.data.uv_layers["UVMap"]


def set_decal_uv(o, fn):
    """Adds a "Decal" UV layer with uv = fn(vertex co) (a vector in object space)."""
    ensure_uv(o)
    layer = o.data.uv_layers.get("Decal") or o.data.uv_layers.new(name="Decal")
    for loop in o.data.loops:
        layer.data[loop.index].uv = fn(o.data.vertices[loop.vertex_index].co)
    o.data.uv_layers.active = o.data.uv_layers["UVMap"]
    return o


def planar_decal_uv(o, axis_u, axis_v):
    """Decal UVs from a planar projection over the object's own bounds
    (axis_u / axis_v are 0, 1, 2 for X, Y, Z; negative = flipped)."""
    cos = [v.co for v in o.data.vertices]

    def span(a):
        vals = [c[a] for c in cos]
        return min(vals), max(vals)

    (u0, u1), (v0, v1) = span(abs(axis_u)), span(abs(axis_v))

    def fn(c):
        u = (c[abs(axis_u)] - u0) / max(u1 - u0, 1e-6)
        v = (c[abs(axis_v)] - v0) / max(v1 - v0, 1e-6)
        return (u, v)
    return set_decal_uv(o, fn)


def decal_paint(name, color, image_path, facing=(1, 0, 0), threshold=0.6, **kw):
    """paint() plus an RGBA decal image read through the "Decal" UV layer, only on
    faces whose normal is within ~50 degrees of +-facing (so sides stay clean)."""
    mat = paint(name, color, **kw)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    link = bsdf.inputs["Base Color"].links
    base = link[0].from_socket if link else None
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = "Decal"
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(image_path, check_existing=False)
    img.extension = "CLIP"
    img.interpolation = "Cubic"
    nt.links.new(uvn.outputs["UV"], img.inputs["Vector"])
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = facing
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    ab = nt.nodes.new("ShaderNodeMath")
    ab.operation = "ABSOLUTE"
    nt.links.new(dot.outputs["Value"], ab.inputs[0])
    gt = nt.nodes.new("ShaderNodeMath")
    gt.operation = "GREATER_THAN"
    gt.inputs[1].default_value = threshold
    nt.links.new(ab.outputs[0], gt.inputs[0])
    mask = nt.nodes.new("ShaderNodeMath")
    mask.operation = "MULTIPLY"
    nt.links.new(gt.outputs[0], mask.inputs[0])
    nt.links.new(img.outputs["Alpha"], mask.inputs[1])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(mask.outputs[0], mix.inputs["Factor"])
    if base is not None:
        nt.links.new(base, mix.inputs["A"])
    else:
        mix.inputs["A"].default_value = bsdf.inputs["Base Color"].default_value[:]
    nt.links.new(img.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    return mat


# ---------------------------------------------------------------- blades
def blade(name, mat, y0, length, width, thick=0.1, edge=0.012, bevel=0.1, clip=0.45, chisel=0.16,
          curve=0.0, stations=14, width_fn=None, bend_fn=None, spine_bevel=0.0):
    """Katana/dao blade along +Y from y0 (flat faces +-X, edge at -Z, spine at +Z).
    Cross-section: flat faces from the spine to a bevel line, then a bevel to a thin edge.
    The tip is clipped: the spine side reaches y0 + length, the edge side `clip` lower,
    with a `chisel` wide bevel under the clip line. Decal UVs: u 0 edge -> 1 spine,
    v 0 base -> 1 tip, set before bending so ornaments follow the curve."""
    wf = width_fn or (lambda s: 1.0)

    def ring(y, s, taper=1.0):
        w = width * wf(s)
        h = thick / 2 * taper
        e = edge / 2 * taper
        zs, ze, zb = w / 2, -w / 2, -w / 2 + bevel * wf(s)
        sb = spine_bevel
        return [(h - sb, y, zs), (h, y, zs - sb), (h, y, zb), (e, y, ze), (-e, y, ze), (-h, y, zb), (-h, y, zs - sb), (-h + sb, y, zs)]

    L_e = length - clip  # where the edge side stops
    verts, rings = [], []
    ys = [y0 + L_e * (i / stations) for i in range(stations)]
    lo_e, lo_s = L_e - chisel, length - chisel
    for y in ys:
        s = (y - y0) / length
        if y - y0 >= lo_e - 1e-6:
            break
        rings.append(list(range(len(verts), len(verts) + 8)))
        verts += ring(y, s)
    # bevel-start ring (slanted) and the clipped ridge (thin)
    for lo, hi, taper in ((lo_e, lo_s, 1.0), (L_e, length, 0.08)):
        rs = ring(0, 0, taper)
        out = []
        for (x, _, z) in rs:
            w = width * wf(1.0)
            f = min(1, max(0, (z + w / 2) / w))
            yy = y0 + lo + (hi - lo) * f
            out.append((x, yy, z))
        rings.append(list(range(len(verts), len(verts) + 8)))
        verts += out
    faces = C.loft(rings)
    o = flat(name, verts, faces, mat)
    Lw = length

    def uv(c):
        s = (c.y - y0) / Lw
        w = width * wf(min(max(s, 0), 1))
        return ((c.z + w / 2) / w, s)
    set_decal_uv(o, uv)
    if curve or bend_fn:
        for v in o.data.vertices:
            s = max(0.0, (v.co.y - y0) / length)
            if bend_fn:
                v.co.z += bend_fn(s)
            else:
                v.co.z += curve * s * s
        o.data.update()
    return o


def triangulate(o):
    """Triangulate in Blender (beauty) so Studio never has to split concave n-gons."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(o.data)
    bm.free()
    return o
