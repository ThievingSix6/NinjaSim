"""Shape helpers shared by the NinjaSim character scripts (outfit.py, enemies.py):
hollow superellipse bands, flat ribbons along paths, swept tubes and superellipsoid shells."""
import math

import bpy
import bmesh
from mathutils import Vector

import common as C


def solidify(o, thick, offset=1.0):
    mod = o.modifiers.new("S", "SOLIDIFY")
    mod.thickness = thick
    mod.offset = offset
    C.apply_modifiers(o)
    C.recalc_normals(o)
    return o


def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def superellipse(hx, hy, n=28, power=4.0, phase=0.0):
    pts = []
    for k in range(n):
        a = phase + 2 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        pts.append((hx * math.copysign(abs(c) ** (2 / power), c), hy * math.copysign(abs(s) ** (2 / power), s)))
    return pts


def tube(name, stations, mat, n=28, power=4.0, thick=0.05, center=(0, 0, 0), arc=None):
    """Hollow band. stations = [(z, hx, hy)]. arc=(a0, a1) keeps only part of the ring (open strip)."""
    cx, cy, cz = center
    verts, rings = [], []
    for (z, hx, hy) in stations:
        ring = []
        if arc:
            a0, a1 = arc
            for k in range(n + 1):
                a = a0 + (a1 - a0) * k / n
                c, s = math.cos(a), math.sin(a)
                x, y = hx * math.copysign(abs(c) ** (2 / power), c), hy * math.copysign(abs(s) ** (2 / power), s)
                ring.append(len(verts))
                verts.append((cx + x, cy + y, cz + z))
        else:
            for (x, y) in superellipse(hx, hy, n, power):
                ring.append(len(verts))
                verts.append((cx + x, cy + y, cz + z))
        rings.append(ring)
    faces = []
    m = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(m if not arc else m - 1):
            j = (i + 1) % m
            faces.append((a[i], a[j], b[j], b[i]))
    o = C.mesh_object(name, verts, faces, mat)
    smooth(o)
    return solidify(o, thick, 1.0)


def ribbon(name, pts, normals, widths, thick, mat, smooth_it=True):
    """Flat strip along pts; each point's `normal` is the strip's face direction."""
    pts = [Vector(p) for p in pts]
    normals = [Vector(nm).normalized() for nm in normals]
    verts, rings = [], []
    n = len(pts)
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        nm = normals[i]
        nm = (nm - t * nm.dot(t)).normalized()
        across = nm.cross(t).normalized()
        w = widths[i] / 2 if isinstance(widths, (list, tuple)) else widths / 2
        ring = []
        for (sa, sn) in ((-1, -0.5), (1, -0.5), (1, 0.5), (-1, 0.5)):
            ring.append(len(verts))
            verts.append(p + across * (sa * w) + nm * (sn * thick))
        rings.append(ring)
    o = C.mesh_object(name, verts, C.loft(rings), mat)
    C.recalc_normals(o)
    if smooth_it:
        C.shade_auto(o, 50)
    return o


def swept(name, pts, radii, mat, n=12):
    """Round tube along a path with per-point radius (horns, knots)."""
    pts = [Vector(p) for p in pts]
    verts, rings = [], []
    up = Vector((0, 0, 1))
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        a = up.cross(t)
        if a.length < 1e-4:
            a = Vector((1, 0, 0)).cross(t)
        a.normalize()
        b = t.cross(a).normalized()
        ring = []
        for k in range(n):
            ang = 2 * math.pi * k / n
            ring.append(len(verts))
            verts.append(p + (a * math.cos(ang) + b * math.sin(ang)) * max(radii[i], 0.004))
        rings.append(ring)
    o = C.mesh_object(name, verts, C.loft(rings), mat)
    C.recalc_normals(o)
    return smooth(o)


def shell(name, radius, scale, center, keep_fn, mat, thick=0.045, segs=40, rings=26, power=2.0):
    """Superellipsoid shell (power 2 = sphere, higher = boxier) with faces kept by keep_fn(centre)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for v in bm.verts:
        d = [math.copysign(abs(c) ** (2 / power), c) * radius for c in v.co]
        v.co = Vector((d[0] * scale[0] + center[0], d[1] * scale[1] + center[1], d[2] * scale[2] + center[2]))
    kill = [f for f in bm.faces if not keep_fn(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    smooth(o)
    return solidify(o, thick, -1.0)
