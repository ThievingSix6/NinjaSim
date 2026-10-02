"""Texture baking for the textured "hero" models (hero_katanas.py, heroes.py).

Models are built from many objects with simple procedural materials. `bake_atlas`
lays every object out in one shared UV atlas, bakes their colours plus ambient
occlusion into a single PNG, then swaps all materials for one textured material, so
Studio's Import 3D uploads one image per model and the game keeps it (Assets.Textured).

  atlas_uv(objs, weights)     one UV layout for all objects (weights: name -> texel scale)
  bake_atlas(objs, png, ...)  colour x AO -> png, objs now share material `name`
"""
import math

import bpy
import numpy as np


def _set_active(objs):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def _uv_area_ratio(o):
    """3D area / UV area of an object (texel density), from its active UV map."""
    me = o.data
    uv = me.uv_layers.active.data
    a3 = auv = 0.0
    for p in me.polygons:
        a3 += p.area
        pts = [uv[li].uv for li in p.loop_indices]
        s = 0.0
        for i in range(len(pts)):
            x1, y1 = pts[i]
            x2, y2 = pts[(i + 1) % len(pts)]
            s += x1 * y2 - x2 * y1
        auv += abs(s) / 2
    return a3 / max(auv, 1e-12)


def atlas_uv(objs, weights=None, angle=66, margin=0.006):
    """Smart-projects every object, evens texel density (times `weights[name]`,
    e.g. 1.8 for a face), then packs all islands of all objects into one 0-1 square."""
    weights = weights or {}
    for o in objs:
        if "UVMap" not in o.data.uv_layers:
            o.data.uv_layers.new(name="UVMap")
        o.data.uv_layers.active = o.data.uv_layers["UVMap"]
    for o in objs:
        _set_active([o])
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=0.002, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
    # even out texel density across objects: scale each object's UVs so that
    # (uv area / 3D area) matches, times its weight
    ratios = {o.name: _uv_area_ratio(o) for o in objs}
    ref = min(ratios.values())
    for o in objs:
        k = math.sqrt(ratios[o.name] / ref) * weights.get(o.name, 1.0)
        uv = o.data.uv_layers.active.data
        for d in uv:
            d.uv = (d.uv[0] * k, d.uv[1] * k)
    _set_active(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, scale=True, margin_method="FRACTION", margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def _bake(objs, image, kind, samples, margin):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.render.bake.margin = margin
    scene.render.bake.use_clear = True
    nodes = []
    for o in objs:
        for slot in o.material_slots:
            mat = slot.material
            if mat is None:
                continue
            mat.use_nodes = True
            nt = mat.node_tree
            n = nt.nodes.get("__bake__")
            if n is None:
                n = nt.nodes.new("ShaderNodeTexImage")
                n.name = "__bake__"
                nodes.append((nt, n))
            n.image = image
            nt.nodes.active = n
    _set_active(objs)
    if kind == "COLOR":
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=margin, use_clear=True)
    elif kind == "EMIT":
        bpy.ops.object.bake(type="EMIT", margin=margin, use_clear=True)
    else:
        bpy.ops.object.bake(type="AO", margin=margin, use_clear=True)
    for nt, n in nodes:
        nt.nodes.remove(n)


def _pixels(image):
    w, h = image.size
    a = np.empty(w * h * 4, dtype=np.float32)
    image.pixels.foreach_get(a)
    return a.reshape(h, w, 4)


def _blur(a, r):
    """Box blur (radius r px) to take the grain out of the AO bake."""
    if r <= 0:
        return a
    out = a.copy()
    for axis in (0, 1):
        acc = np.zeros_like(out)
        for k in range(-r, r + 1):
            acc += np.roll(out, k, axis=axis)
        out = acc / (2 * r + 1)
    return out


def bake_atlas(objs, png, name, size=1024, ao=0.55, ao_samples=96, ao_distance=0.25, weights=None, uv=True, glow_objs=(), blur=1):
    """Bakes colour x AO for `objs` into `png`; afterwards they all use one material
    `name` that shows that image. `glow_objs` keep their own (neon) materials and
    are left out of the atlas."""
    objs = [o for o in objs if o not in glow_objs]
    if uv:
        atlas_uv(objs, weights)
    # Bake one joined copy: Blender dilates the margin per object, so baking many
    # objects into one image lets each object's margin paint over its neighbours.
    copies = []
    for ob in objs:
        c = ob.copy()
        c.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(c)
        copies.append(c)
    _set_active(copies)
    bpy.ops.object.join()
    joined = copies[0]
    color = bpy.data.images.new(name + "_col", size, size, alpha=False)
    occl = bpy.data.images.new(name + "_ao", size, size, alpha=False, float_buffer=True)
    occl.colorspace_settings.name = "Non-Color"
    _bake([joined], color, "COLOR", 1, 12)
    world = bpy.context.scene.world or bpy.data.worlds.new("BakeWorld")
    bpy.context.scene.world = world
    world.light_settings.distance = ao_distance
    _bake([joined], occl, "AO", ao_samples, 12)
    bpy.data.objects.remove(joined)
    c = _pixels(color)
    o = _blur(_pixels(occl)[..., :1], blur)
    shade = 1.0 - ao * (1.0 - np.clip(o, 0, 1))
    out = c.copy()
    out[..., :3] = np.clip(c[..., :3] * shade, 0, 1)
    out[..., 3] = 1.0
    final = bpy.data.images.new(name, size, size, alpha=False)
    final.pixels.foreach_set(out.ravel())
    final.filepath_raw = png
    final.file_format = "PNG"
    final.save()
    bpy.data.images.remove(color)
    bpy.data.images.remove(occl)
    final.filepath = png
    final.source = "FILE"
    final.reload()
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.6
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = final
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    for ob in objs:
        ob.data.materials.clear()
        ob.data.materials.append(mat)
    return mat
