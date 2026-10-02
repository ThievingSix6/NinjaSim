"""Shared state and helpers for the v2 sculpted packs (enemies.py and friends):
one material table, the list of exported objects, grouping with a triangle budget,
and a few placement tools (straps that hug a body, ray-cast surface points)."""
import math

import bpy
from mathutils import Vector

import common as C
import sculpt as S
from common import rgb

M = {
    "cloth": C.material("KCloth", rgb(70, 60, 90), roughness=0.9, roblox="Fabric"),
    "skin": C.material("KSkin", rgb(230, 186, 150), roughness=0.7, roblox="SmoothPlastic"),
    "trim": C.material("KTrim", rgb(200, 60, 50), roughness=0.8, roblox="Fabric"),
    "wrap": C.material("KWrap", rgb(215, 200, 175), roughness=0.9, roblox="Fabric"),
    "dark": C.material("KDark", rgb(30, 24, 24), roughness=0.8, roblox="SmoothPlastic"),
    "metal": C.material("KMetal", rgb(90, 90, 100), metallic=0.7, roughness=0.35, roblox="Metal"),
    "gold": C.material("KGold", rgb(230, 190, 80), metallic=0.8, roughness=0.3, roblox="Foil"),
    "straw": C.material("KStraw", rgb(214, 186, 120), roughness=0.9, roblox="Fabric"),
    "wood": C.material("KWood", rgb(110, 76, 48), roughness=0.8, roblox="Wood"),
    "glow": C.material("KGlow", rgb(255, 120, 60), emission=rgb(255, 120, 60), strength=3.0, roblox="Neon"),
    "eyes": C.material("KEyes", rgb(255, 230, 120), emission=rgb(255, 230, 120), strength=2.0, roblox="Neon"),
    "fur": C.material("KFur", rgb(235, 140, 60), roughness=0.9, roblox="SmoothPlastic"),
    "fluff": C.material("KFluff", rgb(250, 240, 225), roughness=0.9, roblox="SmoothPlastic"),
    "rock": C.material("KRock", rgb(90, 80, 76), roughness=0.95, roblox="Slate"),
    "bone": C.material("KBone", rgb(240, 232, 212), roughness=0.5, roblox="SmoothPlastic"),
    "lacquer": C.material("KLacquer", rgb(150, 30, 30), metallic=0.2, roughness=0.35, roblox="SmoothPlastic"),
}
objects = []


def group(name, parts, mat, tris=None):
    """Merge parts into one exported mesh (one colour in game), optionally decimated."""
    o = C.merge(parts, name, M[mat]) if len(parts) > 1 else parts[0]
    o.name = name
    o.data.name = name
    o.data.materials.clear()
    o.data.materials.append(M[mat])
    if tris:
        o = S.budget(o, tris)
        o.name = name
        o.data.name = name
    objects.append(o)
    return o


def band_on(name, pts, normals, width, target, mat, thick=0.045, offset=0.012):
    """A strap that hugs `target`: flat strip -> shrinkwrap -> thickness outward."""
    pts = [Vector(p) for p in pts]
    verts, faces = [], []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = Vector(normals[i]).normalized()
        n = (n - t * n.dot(t)).normalized()
        a = n.cross(t).normalized()
        verts += [p - a * width / 2, p + a * width / 2]
    for i in range(len(pts) - 1):
        k = 2 * i
        faces.append((k, k + 2, k + 3, k + 1))
    o = C.mesh_object(name, verts, faces, M[mat])
    sub = o.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    o = S._bake(o, name, M[mat])
    o = S.shrink_onto(o, target, offset)
    s = o.modifiers.new("S", "SOLIDIFY")
    s.thickness = thick
    s.offset = 1.0
    return S._bake(o, name, M[mat])


def mirrored(src, name):
    """Left-side copy of a right-side piece (Roblox can't mirror MeshParts), exported too."""
    o = S.mirror_x(src, name)
    o.data.name = name
    objects.append(o)
    return o


def place(o, loc=(0, 0, 0), rot=(0, 0, 0)):
    o.rotation_euler = rot
    o.location = loc
    C.apply_transforms([o])
    return o


def star(name, r_out, r_in, thick, mat, points=4):
    pts = []
    for k in range(points * 2):
        a = math.pi / 2 + k * math.pi / points
        r = r_out if k % 2 == 0 else r_in
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return C.extrude_outline(name, pts, thick, M[mat], axis="Y", bevel=0.008)


def hit(obj, origin, direction):
    """First surface point of obj along a ray (object space = world, transforms applied)."""
    ok, loc, nrm, _ = obj.ray_cast(Vector(origin), Vector(direction).normalized())
    return (Vector(loc), Vector(nrm)) if ok else (None, None)


def front_y(obj, x, z, default=0.5):
    loc, _ = hit(obj, (x, 5.0, z), (0, -1, 0))
    return loc.y if loc else default


def dent(centres, radius, depth):
    """Displacement fn: push the surface in around each centre (eye sockets, navels)."""
    cs = [Vector(c) for c in centres]

    def fn(co, n):
        d = 0.0
        for c in cs:
            r = (co - c).length
            if r < radius:
                d -= depth * (1 - (r / radius) ** 2) ** 2
        return d
    return fn


def almond(name, w, h, mat, side, tilt=18, thick=0.04, angry=0.45):
    """Flat almond eye facing +Y; `angry` flattens the inner-top edge into a glare."""
    outline = []
    for k in range(18):
        a = math.tau * k / 18
        u = w * math.cos(a)
        v = h * math.sin(a)
        if v > 0:
            v *= 1.0 - angry * max(0.0, -math.cos(a) * side)
        outline.append((u, v))
    e = C.extrude_outline(name, outline, thick, M[mat], axis="Y")
    e.rotation_euler = (0, math.radians(side * -tilt), 0)
    C.apply_transforms([e])
    return e


def budget_all(parts, tris):
    return [S.budget(p, tris) for p in parts]


__all__ = ["M", "objects", "group", "mirrored", "band_on", "place", "star", "hit", "front_y", "dent", "almond", "rgb"]
