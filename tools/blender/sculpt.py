"""Organic modelling helpers for NinjaSim (headless bpy): metaball blobs, skin-modifier
limbs, voxel fusing, cloth folds and polygon budgets. Everything returns a plain mesh
object with modifiers applied, ready for common.merge / export."""
import math
import random

import bpy
import bmesh
from mathutils import Euler, Vector
from mathutils.noise import noise as perlin

import common as C


def _link(name, mesh, mat):
    o = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(o)
    if mat is not None:
        o.data.materials.clear()
        o.data.materials.append(mat)
    return o


def _bake(o, name, mat):
    """Evaluate modifiers / metaballs into a new mesh object and drop the source."""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    bpy.data.objects.remove(o)
    out = _link(name, mesh, mat)
    for p in out.data.polygons:
        p.use_smooth = True
    return out


def blobs(name, elements, mat, resolution=0.05, threshold=0.6):
    """Metaball union. elements: dicts with type BALL/ELLIPSOID/CAPSULE, co, radius,
    size (x, y, z) for ellipsoids / size_x for capsules, rot (euler), stiffness, negative."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = threshold
    o = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(o)
    for spec in elements:
        e = mb.elements.new(type=spec.get("type", "BALL"))
        e.co = spec["co"]
        e.radius = spec.get("radius", 1.0)
        e.stiffness = spec.get("stiffness", 2.0)
        e.use_negative = spec.get("negative", False)
        if "size" in spec:
            e.size_x, e.size_y, e.size_z = spec["size"]
        if "size_x" in spec:
            e.size_x = spec["size_x"]
        if "rot" in spec:
            e.rotation = Euler(spec["rot"]).to_quaternion()
    return _bake(o, name, mat)


def skin(name, verts, edges, radii, mat, subdiv=2, root=0):
    """Skin-modifier tube network (limbs, tails, branches, horns) smoothed by subdivision."""
    m = bpy.data.meshes.new(name)
    m.from_pydata([tuple(v) for v in verts], [tuple(e) for e in edges], [])
    o = _link(name, m, None)
    o.modifiers.new("Skin", "SKIN")
    sv = o.data.skin_vertices[0].data
    for i, r in enumerate(radii):
        sv[i].radius = r if isinstance(r, (tuple, list)) else (r, r)
    sv[root].use_root = True
    if subdiv:
        s = o.modifiers.new("Sub", "SUBSURF")
        s.levels = subdiv
        s.render_levels = subdiv
    return _bake(o, name, mat)


def subdivide(o, levels=2):
    s = o.modifiers.new("Sub", "SUBSURF")
    s.levels = levels
    s.render_levels = levels
    return _bake(o, o.name, o.data.materials[0] if o.data.materials else None)


def fuse(objs, name, mat, voxel=0.03, smooth=6, smooth_factor=0.6):
    """Voxel-remesh several overlapping solids into one seamless sculpted surface."""
    o = C.join(objs, name) if len(objs) > 1 else objs[0]
    r = o.modifiers.new("R", "REMESH")
    r.mode = "VOXEL"
    r.voxel_size = voxel
    r.use_smooth_shade = True
    if smooth:
        s = o.modifiers.new("S", "SMOOTH")
        s.iterations = smooth
        s.factor = smooth_factor
    return _bake(o, name, mat)


def budget(o, tris):
    """Decimate to roughly `tris` triangles (collapse keeps the silhouette)."""
    now = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if now <= tris:
        return o
    d = o.modifiers.new("D", "DECIMATE")
    d.ratio = max(0.02, tris / now)
    return _bake(o, o.name, o.data.materials[0] if o.data.materials else None)


def displace(o, fn):
    """Move every vertex along its normal by fn(co, normal)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.normal_update()
    moves = [(v, v.normal.copy() * fn(v.co.copy(), v.normal.copy())) for v in bm.verts]
    for v, d in moves:
        v.co += d
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    return o


def folds(axis="Z", count=7, depth=0.03, around=True, center=(0, 0), wobble=0.0, seed=0):
    """Cloth pleats: sine ripples around an axis (vertical pleats) or along it (rings)."""
    rnd = random.Random(seed)
    phase = rnd.uniform(0, math.tau)

    def fn(co, n):
        if around:
            a = math.atan2(co.y - center[1], co.x - center[0]) if axis == "Z" else math.atan2(co.z - center[1], co.x - center[0])
            w = math.sin(a * count + phase + wobble * perlin(co * 3))
        else:
            t = co.z if axis == "Z" else co.y
            w = math.sin(t * count + phase + wobble * perlin(co * 3))
        return depth * w
    return fn


def roughen(scale=3.0, depth=0.03, seed=0):
    off = Vector((seed * 7.1, seed * 3.3, seed * 1.7))

    def fn(co, n):
        return depth * perlin(co * scale + off)
    return fn


def shrink_onto(o, target, offset=0.02):
    """Project o onto target's surface (lapels, straps and seams that hug a body)."""
    m = o.modifiers.new("W", "SHRINKWRAP")
    m.target = target
    m.wrap_method = "NEAREST_SURFACEPOINT"
    m.wrap_mode = "OUTSIDE_SURFACE"
    m.offset = offset
    return _bake(o, o.name, o.data.materials[0] if o.data.materials else None)


def strap(name, pts, width, thick, mat, up=(0, 0, 1)):
    """Flat band through pts whose width runs across `up` x tangent (belts, wraps)."""
    pts = [Vector(p) for p in pts]
    verts, rings = [], []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        u = Vector(up)
        side = t.cross(u).normalized()
        nrm = side.cross(t).normalized()
        ring = []
        for (a, b) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            ring.append(len(verts))
            verts.append(p + nrm * (a * width / 2) + side * (b * thick / 2))
        rings.append(ring)
    o = C.mesh_object(name, verts, C.loft(rings), mat)
    C.recalc_normals(o)
    return o


def spiral_wrap(name, z0, z1, radius, turns, width, thick, mat, center=(0, 0), steps=80, taper=0.0):
    """A cloth strip wound around a limb from z0 to z1 (bandages, grip wraps)."""
    verts, rings = [], []
    for i in range(steps + 1):
        t = i / steps
        a = t * turns * math.tau
        r = radius * (1 - taper * t)
        z = z0 + (z1 - z0) * t
        c = Vector((center[0] + math.cos(a) * r, center[1] + math.sin(a) * r, z))
        out = Vector((math.cos(a), math.sin(a), 0))
        up = Vector((0, 0, 1))
        ring = []
        for (da, db) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            ring.append(len(verts))
            verts.append(c + up * (da * width / 2) + out * (db * thick / 2))
        rings.append(ring)
    o = C.mesh_object(name, verts, C.loft(rings), mat)
    C.recalc_normals(o)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def ellipsoid(name, half, center, mat, power=2.0, rot=None, segs=28, rings=18):
    """Superellipsoid solid (power 2 = ellipsoid, higher = boxier), optionally rotated (euler)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for v in bm.verts:
        d = [math.copysign(abs(c) ** (2 / power), c) for c in v.co]
        v.co = Vector((d[0] * half[0], d[1] * half[1], d[2] * half[2]))
    if rot:
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Euler(rot).to_matrix())
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector(center))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    o = _link(name, mesh, mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def lofted(name, stations, mat, power=2.0, n=32, caps=True):
    """Solid through superellipse rings: stations = [(z, hx, hy)] or [(z, hx, hy, cx, cy)]."""
    verts, rings = [], []
    for st in stations:
        z, hx, hy = st[0], st[1], st[2]
        cx, cy = (st[3], st[4]) if len(st) > 3 else (0.0, 0.0)
        ring = []
        for k in range(n):
            a = math.tau * k / n
            c, s = math.cos(a), math.sin(a)
            ring.append(len(verts))
            verts.append((cx + hx * math.copysign(abs(c) ** (2 / power), c), cy + hy * math.copysign(abs(s) ** (2 / power), s), z))
        rings.append(ring)
    o = C.mesh_object(name, verts, C.loft(rings, cap_start=caps, cap_end=caps), mat)
    C.recalc_normals(o)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def extract(src, name, keep, mat, offset=0.05, thick=0.05):
    """Copy the faces of src whose centre passes keep(co, normal), push them out by
    `offset` and give them thickness: armour plates and panels that follow a body."""
    bm = bmesh.new()
    bm.from_mesh(src.data)
    bm.normal_update()
    kill = [f for f in bm.faces if not keep(f.calc_center_median(), f.normal)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    for v in bm.verts:
        v.co += v.normal * offset
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    o = _link(name, mesh, mat)
    s = o.modifiers.new("S", "SOLIDIFY")
    s.thickness = thick
    s.offset = 1.0
    o = _bake(o, name, mat)
    C.recalc_normals(o)
    return o


def mirror_x(o, name):
    """Left-hand copy of a right-hand piece (Roblox can't mirror MeshParts)."""
    m = o.data.copy()
    m.transform(__import__("mathutils").Matrix.Scale(-1, 4, (1, 0, 0)))
    m.flip_normals()
    return _link(name, m, o.data.materials[0] if o.data.materials else None)
