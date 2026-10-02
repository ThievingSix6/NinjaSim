"""NinjaSim UI icon set: chunky glossy cartoon icons rendered with Cycles (headless bpy).

Run from tools/blender:
    python3 icons.py                 # render all icons, then rebuild atlas / Lua / FBX / contact sheet
    python3 icons.py Coin Shard      # re-render just those, then rebuild everything from the PNGs on disk
    python3 icons.py --pack          # only rebuild atlas / Lua / FBX / contact sheet

Outputs (paths relative to the project root):
    assets/icons/<Name>.png            166x166 RGBA, one per icon
    assets/icons/UIIcons.png           1024x1024 atlas, 6x6 grid of 170px cells
    src/shared/Visuals/IconAtlas.lua   pixel rects of each icon in the atlas
    assets/NinjaSim_UIIcons.fbx        textured plate "UIIconAtlas" (atlas embedded) for Studio import
    assets/previews/ui_icons.png       contact sheet (full size + 48px, grey and gradient backgrounds)

Every icon is modelled around the origin with -Y facing the camera and +Z up, then normalised to
the same size, so one camera and one light rig serve the whole set.
"""
import json
import math
import os
import sys
import time

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector
from mathutils.geometry import delaunay_2d_cdt
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ICON_DIR = os.path.join(ROOT, "assets", "icons")
ATLAS_PATH = os.path.join(ICON_DIR, "UIIcons.png")
LUA_PATH = os.path.join(ROOT, "src", "shared", "Visuals", "IconAtlas.lua")
FBX_PATH = os.path.join(ROOT, "assets", "NinjaSim_UIIcons.fbx")
SHEET_PATH = os.path.join(ROOT, "assets", "previews", "ui_icons.png")
SCRATCH = os.environ.get("ICON_SCRATCH", "/tmp/claude-0/icons_scratch")

RENDER = 512          # render size (px)
ICON = 166            # final icon size (px)
CELL = 170            # atlas cell size (px)
ATLAS = 1024
COLS = 6
OUTLINE_PX = 14       # outline width at render size
OUTLINE_RGB = (26, 22, 40)
FILL = 0.88           # icon + outline spans this fraction of the square
SAMPLES = 48

CAM_DIR = Vector((0.0, -1.0, math.tan(math.radians(20)))).normalized()
CAM_DIST = 9.0


# ----------------------------------------------------------------------------------------------
# materials
# ----------------------------------------------------------------------------------------------

def M(name, col, rough=0.32, metal=0.0, coat=0.35, emit=0.0, spec=0.5, edge=None, edge_amt=0.75):
    """Glossy toy-plastic material. col is sRGB 0-255. `edge` tints surfaces seen edge-on
    (a cartoon hue shift, e.g. orange rims on gold)."""
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    lin = C.rgb(*col)
    mat = C.material(name, lin, metallic=metal, roughness=rough)
    nt = mat.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.08
    b.inputs["Specular IOR Level"].default_value = spec
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*lin, 1.0)
        b.inputs["Emission Strength"].default_value = emit
    if edge is not None:
        lw = nt.nodes.new("ShaderNodeLayerWeight")
        lw.inputs["Blend"].default_value = 0.5
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = 0.25
        mr.inputs["From Max"].default_value = 1.0
        mr.inputs["To Max"].default_value = edge_amt
        nt.links.new(lw.outputs["Facing"], mr.inputs["Value"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs["A"].default_value = (*lin, 1)
        mix.inputs["B"].default_value = (*C.rgb(*edge), 1)
        nt.links.new(mr.outputs["Result"], mix.inputs["Factor"])
        nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
    return mat


def spot_material(name, base, spots, rough=0.32, coat=0.35):
    """Glossy material with round painted spots: spots = [((x, y, z) object-space centre, radius, col)]."""
    mat = M(name, base, rough=rough, coat=coat)
    nt = mat.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    prev = None
    for (c, r, col) in spots:
        dist = nt.nodes.new("ShaderNodeVectorMath")
        dist.operation = "DISTANCE"
        nt.links.new(tc.outputs["Object"], dist.inputs[0])
        dist.inputs[1].default_value = c
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = r - 0.012
        mr.inputs["From Max"].default_value = r + 0.012
        mr.inputs["To Min"].default_value = 1.0
        mr.inputs["To Max"].default_value = 0.0
        nt.links.new(dist.outputs["Value"], mr.inputs["Value"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        nt.links.new(mr.outputs["Result"], mix.inputs["Factor"])
        if prev is None:
            mix.inputs["A"].default_value = (*C.rgb(*base), 1)
        else:
            nt.links.new(prev.outputs["Result"], mix.inputs["A"])
        mix.inputs["B"].default_value = (*C.rgb(*col), 1)
        prev = mix
    if prev is not None:
        nt.links.new(prev.outputs["Result"], b.inputs["Base Color"])
    return mat


# ----------------------------------------------------------------------------------------------
# 2D outline helpers (u right, v up)
# ----------------------------------------------------------------------------------------------

def circle(r, n=96, c=(0.0, 0.0), a0=0.0, rx=None, ry=None):
    rx = r if rx is None else rx
    ry = r if ry is None else ry
    return [(c[0] + rx * math.cos(a0 + math.tau * i / n), c[1] + ry * math.sin(a0 + math.tau * i / n)) for i in range(n)]


def rect(w, h, c=(0.0, 0.0)):
    x, y = c
    return [(x - w / 2, y - h / 2), (x + w / 2, y - h / 2), (x + w / 2, y + h / 2), (x - w / 2, y + h / 2)]


def star_pts(n, r_out, r_in, rot=90.0):
    pts = []
    for i in range(2 * n):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rot) + math.pi * i / n
        pts.append((r * math.cos(a), r * math.sin(a)))
    return pts


def fillet(pts, r, n=10, closed=True):
    """Round every corner of a polyline with radius r (float, or one per point)."""
    P = [Vector(p) for p in pts]
    N = len(P)
    out = []
    for i in range(N):
        p = P[i]
        if not closed and (i == 0 or i == N - 1):
            out.append(p)
            continue
        rr = r[i] if isinstance(r, (list, tuple)) else r
        a, b = P[i - 1], P[(i + 1) % N]
        if rr <= 0 or (a - p).length < 1e-9 or (b - p).length < 1e-9:
            out.append(p)
            continue
        d1, d2 = (a - p).normalized(), (b - p).normalized()
        ang = math.acos(max(-1.0, min(1.0, d1.dot(d2))))
        if ang > math.pi - 1e-3 or ang < 1e-3:
            out.append(p)
            continue
        t = rr / math.tan(ang / 2)
        t = min(t, 0.5 * (a - p).length, 0.5 * (b - p).length)
        rr = t * math.tan(ang / 2)
        p1, p2 = p + d1 * t, p + d2 * t
        c = p + (d1 + d2).normalized() * (rr / math.sin(ang / 2))
        a1 = math.atan2(p1.y - c.y, p1.x - c.x)
        a2 = math.atan2(p2.y - c.y, p2.x - c.x)
        da = (a2 - a1 + math.pi) % math.tau - math.pi
        for k in range(n + 1):
            aa = a1 + da * k / n
            out.append(Vector((c.x + rr * math.cos(aa), c.y + rr * math.sin(aa))))
    return [(v.x, v.y) for v in out]


def spline(ctrl, per=10, closed=False):
    """Catmull-Rom through control points."""
    P = [Vector(p) for p in ctrl]
    n = len(P)
    out = []
    segs = n if closed else n - 1
    for i in range(segs):
        p0 = P[(i - 1) % n] if closed else P[max(i - 1, 0)]
        p1 = P[i]
        p2 = P[(i + 1) % n]
        p3 = P[(i + 2) % n] if closed else P[min(i + 2, n - 1)]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    if not closed:
        out.append(P[-1])
    return [tuple(v) for v in out]


def stroke(path, width, cap_n=12):
    """Closed outline of a thick stroke along an open 2D path, with round caps."""
    P = [Vector(p) for p in path]
    n = len(P)
    L, R = [], []
    for i in range(n):
        t = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized()
        nrm = Vector((-t.y, t.x))
        w = width[i] if isinstance(width, (list, tuple)) else width
        L.append(P[i] + nrm * w / 2)
        R.append(P[i] - nrm * w / 2)
    out = list(R)
    w_end = width[-1] if isinstance(width, (list, tuple)) else width
    w_beg = width[0] if isinstance(width, (list, tuple)) else width
    t = (P[-1] - P[-2]).normalized()
    a0 = math.atan2(-t.x, t.y) + math.pi  # angle of the right-hand normal
    for k in range(1, cap_n):
        a = a0 + math.pi * k / cap_n
        out.append(P[-1] + Vector((math.cos(a), math.sin(a))) * w_end / 2)
    out += list(reversed(L))
    t = (P[1] - P[0]).normalized()
    a0 = math.atan2(t.x, -t.y) + math.pi  # angle of the left-hand normal at the start
    for k in range(1, cap_n):
        a = a0 + math.pi * k / cap_n
        out.append(P[0] + Vector((math.cos(a), math.sin(a))) * w_beg / 2)
    return [(v.x, v.y) for v in out]


def transform2d(pts, scale=1.0, rot=0.0, off=(0.0, 0.0)):
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    sx, sy = (scale, scale) if not isinstance(scale, (tuple, list)) else scale
    return [(off[0] + (x * sx) * c - (y * sy) * s, off[1] + (x * sx) * s + (y * sy) * c) for (x, y) in pts]


def union_outline(polys, res=0.005, ss=4, min_pts=24):
    """Outline loops of the union of several closed 2D polygons (raster + marching squares)."""
    allp = np.concatenate([np.array(p, dtype=float) for p in polys])
    lo = allp.min(0) - 4 * res
    hi = allp.max(0) + 4 * res
    W = int(math.ceil((hi[0] - lo[0]) / res)) + 1
    H = int(math.ceil((hi[1] - lo[1]) / res)) + 1
    img = Image.new("L", (W * ss, H * ss), 0)
    dr = ImageDraw.Draw(img)
    for p in polys:
        dr.polygon([((x - lo[0]) / res * ss, (hi[1] - y) / res * ss) for x, y in p], fill=255)
    f = np.asarray(img.resize((W, H), Image.BOX), dtype=float) / 255.0
    ins = f > 0.5

    def pos(key):
        kind, r, c = key
        if kind == "h":
            a, b = f[r, c], f[r, c + 1]
            t = (0.5 - a) / (b - a)
            x, y = c + t, r
        else:
            a, b = f[r, c], f[r + 1, c]
            t = (0.5 - a) / (b - a)
            x, y = c, r + t
        return (lo[0] + (x + 0.5) * res, hi[1] - (y + 0.5) * res)

    adj = {}

    def link(k1, k2):
        adj.setdefault(k1, []).append(k2)
        adj.setdefault(k2, []).append(k1)

    code = ins[:-1, :-1] * 1 + ins[:-1, 1:] * 2 + ins[1:, 1:] * 4 + ins[1:, :-1] * 8
    rs, cs = np.nonzero((code != 0) & (code != 15))
    for r, c in zip(rs.tolist(), cs.tolist()):
        tl, tr, br, bl = ins[r, c], ins[r, c + 1], ins[r + 1, c + 1], ins[r + 1, c]
        top, bot, left, right = ("h", r, c), ("h", r + 1, c), ("v", r, c), ("v", r, c + 1)
        edges = [e for e, cross in ((top, tl != tr), (right, tr != br), (bot, bl != br), (left, tl != bl)) if cross]
        if len(edges) == 2:
            link(*edges)
        elif len(edges) == 4:
            centre = (f[r, c] + f[r, c + 1] + f[r + 1, c + 1] + f[r + 1, c]) / 4 > 0.5
            for corner, e1, e2 in ((tl, top, left), (tr, top, right), (br, right, bot), (bl, bot, left)):
                if corner != centre:
                    link(e1, e2)
    loops, seen = [], set()
    for start in adj:
        if start in seen:
            continue
        loop, prev, cur = [], None, start
        while cur not in seen:
            seen.add(cur)
            loop.append(pos(cur))
            nxt = [k for k in adj[cur] if k != prev]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
        if len(loop) >= min_pts:
            loops.append(loop)
    loops.sort(key=lambda l: -abs(0.5 * sum(l[i][0] * l[i - 1][1] - l[i - 1][0] * l[i][1] for i in range(len(l)))))
    return loops


# ----------------------------------------------------------------------------------------------
# inflated ("puffy") solids from 2D outlines
# ----------------------------------------------------------------------------------------------

def _resample(loop, step):
    P = np.array(loop, dtype=float)
    Q = np.vstack([P, P[:1]])
    seg = np.linalg.norm(np.diff(Q, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    total = cum[-1]
    m = max(16, int(round(total / step)))
    s = np.linspace(0, total, m, endpoint=False)
    return np.stack([np.interp(s, cum, Q[:, 0]), np.interp(s, cum, Q[:, 1])], axis=1)


def _inside(P, S):
    out = np.zeros(len(P), dtype=bool)
    ax, ay, bx, by = S[:, 0, 0], S[:, 0, 1], S[:, 1, 0], S[:, 1, 1]
    for i in range(0, len(P), 1500):
        x = P[i:i + 1500, 0:1]
        y = P[i:i + 1500, 1:2]
        cond = (ay[None] > y) != (by[None] > y)
        xint = ax[None] + (y - ay[None]) * (bx - ax)[None] / np.where(np.abs(by - ay) < 1e-12, 1e-12, by - ay)[None]
        out[i:i + 1500] = (np.sum(cond & (x < xint), axis=1) % 2) == 1
    return out


def _dist(P, S):
    A = S[:, 0]
    AB = S[:, 1] - A
    L2 = np.maximum((AB ** 2).sum(1), 1e-18)
    out = np.empty(len(P))
    for i in range(0, len(P), 1500):
        p = P[i:i + 1500]
        AP = p[:, None, :] - A[None]
        t = np.clip((AP * AB[None]).sum(2) / L2[None], 0, 1)
        D = AP - t[..., None] * AB[None]
        out[i:i + 1500] = np.sqrt((D ** 2).sum(2).min(1))
    return out


def circ(s):
    s = np.clip(s, 0.0, 1.0)
    return np.sqrt(np.maximum(0.0, 1 - (1 - s) ** 2))


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def _soft_dist(d, V, S, lo, hi, sigma, rim):
    """Distance to the outline with the medial-axis creases blurred away (Gaussian of the
    signed distance on a raster), blended back to the exact distance near the rim."""
    cell = sigma / 5.0
    pad = 4 * sigma
    xs = np.arange(lo[0] - pad, hi[0] + pad + cell, cell)
    ys = np.arange(lo[1] - pad, hi[1] + pad + cell, cell)
    GX, GY = np.meshgrid(xs, ys)
    G = np.stack([GX.ravel(), GY.ravel()], axis=1)
    sd = _dist(G, S)
    sd[~_inside(G, S)] *= -1
    sd = sd.reshape(GX.shape)
    k = np.arange(-15, 16)
    w = np.exp(-0.5 * (k / 5.0) ** 2)
    w /= w.sum()
    for axis in (0, 1):
        P = np.pad(sd, [(15, 15) if a == axis else (0, 0) for a in (0, 1)], mode="edge")
        acc = np.zeros_like(sd)
        for i, wi in enumerate(w):
            acc += wi * (P[i:i + sd.shape[0], :] if axis == 0 else P[:, i:i + sd.shape[1]])
        sd = acc
    fx = (V[:, 0] - xs[0]) / cell
    fy = (V[:, 1] - ys[0]) / cell
    x0 = np.clip(np.floor(fx).astype(int), 0, len(xs) - 2)
    y0 = np.clip(np.floor(fy).astype(int), 0, len(ys) - 2)
    tx, ty = fx - x0, fy - y0
    b = (sd[y0, x0] * (1 - tx) * (1 - ty) + sd[y0, x0 + 1] * tx * (1 - ty)
         + sd[y0 + 1, x0] * (1 - tx) * ty + sd[y0 + 1, x0 + 1] * tx * ty)
    t = smoothstep(0.15 * rim, 0.7 * rim, d)
    return d + (np.minimum(b, d) - d) * t


def puff(name, loops, mat, thick=0.3, rim=None, dome=0.0, prof=None, step=0.018, back=1.0, rings=7, soft=0.0, wall=0.0):
    """Inflate closed 2D loops (first = outline, rest = holes) into a rounded solid.
    The front surface faces -Y (the camera), 2D v maps to +Z. Height above the midplane is
    wall + prof(d) where d is the distance to the outline; by default a round rim of radius `rim`
    rising by `thick`, plus an optional extra `dome` in the middle. wall > 0 adds straight side
    walls (a rounded-edge extrusion)."""
    loops = [_resample(l, step) for l in loops]
    S = np.concatenate([np.stack([l, np.roll(l, -1, axis=0)], axis=1) for l in loops])
    bnd = np.concatenate(loops)
    rim = thick if rim is None else rim
    # inward normals of the boundary samples
    nrm = []
    for l in loops:
        t = np.roll(l, -1, axis=0) - np.roll(l, 1, axis=0)
        t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-12)
        nrm.append(np.stack([-t[:, 1], t[:, 0]], axis=1))
    nrm = np.concatenate(nrm)
    probe = _inside(bnd + nrm * step * 0.25, S)
    nrm[~probe] *= -1
    cands = []
    for k in range(1, rings + 1):
        delta = rim * (1 - math.cos(0.5 * math.pi * k / rings))
        cands.append((bnd + nrm * delta, delta))
    lo, hi = bnd.min(0), bnd.max(0)
    g = step * 1.5
    ys = np.arange(lo[1] + g / 2, hi[1], g * 0.866)
    grid = []
    for j, y in enumerate(ys):
        xs = np.arange(lo[0] + (g / 2 if j % 2 else 0), hi[0], g)
        grid.append(np.stack([xs, np.full_like(xs, y)], axis=1))
    grid = np.concatenate(grid) if grid else np.zeros((0, 2))
    # accept points with a spatial hash so nothing crowds together
    cell = step * 0.5
    hsh = {}
    acc = []

    def ok(p, rmin):
        cx, cy = int(math.floor(p[0] / cell)), int(math.floor(p[1] / cell))
        rr = int(math.ceil(rmin / cell))
        for dx in range(-rr, rr + 1):
            for dy in range(-rr, rr + 1):
                for q in hsh.get((cx + dx, cy + dy), ()):
                    if (q[0] - p[0]) ** 2 + (q[1] - p[1]) ** 2 < rmin * rmin:
                        return False
        return True

    def add(p):
        key = (int(math.floor(p[0] / cell)), int(math.floor(p[1] / cell)))
        hsh.setdefault(key, []).append(p)
        acc.append(p)

    for p in bnd:
        add(p)
    nb = len(acc)
    for pts, delta in cands:
        ins = _inside(pts, S)
        d = _dist(pts, S)
        good = ins & (d > 0.75 * delta)
        rmin = min(step * 0.55, max(delta * 0.35, step * 0.2))
        for p in pts[good]:
            if ok(p, rmin):
                add(p)
    if len(grid):
        ins = _inside(grid, S)
        d = _dist(grid, S)
        for p, dd in zip(grid[ins], d[ins]):
            if dd > rim * 0.9 and ok(p, g * 0.6):
                add(p)
    pts2 = [Vector((float(p[0]), float(p[1]))) for p in acc]
    edges = []
    off = 0
    for l in loops:
        n = len(l)
        edges += [(off + i, off + (i + 1) % n) for i in range(n)]
        off += n
    vout, _e, fout, orig_v, _oe, _of = delaunay_2d_cdt(pts2, edges, [], 0, 1e-7)
    V = np.array([(v.x, v.y) for v in vout])
    F = np.array([f for f in fout if len(f) == 3])
    cen = V[F].mean(1)
    F = F[_inside(cen, S)]
    d = _dist(V, S)
    isb = np.zeros(len(V), dtype=bool)
    for i, o in enumerate(orig_v):
        if any(oi < nb for oi in o):
            isb[i] = True
    d[isb] = 0.0
    dmax = max(d.max(), 1e-6)
    if prof is None:
        h = thick * circ(d / rim) + dome * circ(d / dmax)
    else:
        h = prof(d, V, dmax)
    h[isb] = 0.0
    if soft > 0:
        d = _soft_dist(d, V, S, lo, hi, soft, min(rim, dmax))
        dmax = max(d.max(), 1e-6)
        if prof is None:
            h = thick * circ(d / rim) + dome * circ(d / dmax)
        else:
            h = prof(d, V, dmax)
        h[isb] = 0.0
    h = h + wall
    verts = [(V[i, 0], -h[i], V[i, 1]) for i in range(len(V))]
    back_idx = {}
    for i in range(len(V)):
        if isb[i] and wall <= 0:
            back_idx[i] = i
        else:
            back_idx[i] = len(verts)
            verts.append((V[i, 0], h[i] * back, V[i, 1]))
    faces = []
    for (a, b, c) in F:
        if wall <= 0 and isb[a] and isb[b] and isb[c]:
            continue
        faces.append((a, c, b))
        faces.append((back_idx[a], back_idx[b], back_idx[c]))
    if wall > 0:
        inmap = {}
        for i, o in enumerate(orig_v):
            for oi in o:
                inmap[oi] = i
        off = 0
        for l in loops:
            n = len(l)
            ob = [inmap[off + i] for i in range(n)]
            off += n
            for i in range(n):
                a, b = ob[i], ob[(i + 1) % n]
                if a != b:
                    faces.append((a, b, back_idx[b], back_idx[a]))
    o = C.mesh_object(name, verts, faces, mat, smooth=True)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    for p in o.data.polygons:
        p.use_smooth = True
    return o


# ----------------------------------------------------------------------------------------------
# 3D primitives
# ----------------------------------------------------------------------------------------------

def smooth_all(o):
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def rbox(name, size, center, r, mat, segs=4):
    """Rounded box with hardened normals (flat faces stay flat, edges round)."""
    o = C.box(name, size, center, mat)
    m = o.modifiers.new("Bevel", "BEVEL")
    m.width = min(r, min(size) * 0.499)
    m.segments = segs
    m.limit_method = "NONE"
    m.harden_normals = True
    smooth_all(o)
    C.apply_modifiers(o)
    return o


def revolve(name, profile, mat, segs=64, smooth=True):
    """Lathe a profile [(r, z)] bottom-to-top around Z. Points with r == 0 become poles."""
    verts, rings = [], []
    for (r, z) in profile:
        if r < 1e-6:
            verts.append((0.0, 0.0, z))
            rings.append([len(verts) - 1] * segs)
        else:
            ring = []
            for s in range(segs):
                a = math.tau * s / segs
                verts.append((r * math.cos(a), r * math.sin(a), z))
                ring.append(len(verts) - 1)
            rings.append(ring)
    faces = []
    for A, B in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            f = []
            for v in (A[i], A[j], B[j], B[i]):
                if v not in f:
                    f.append(v)
            if len(f) >= 3:
                faces.append(tuple(f))
    if len(set(rings[0])) > 1:
        faces.append(tuple(reversed(rings[0])))
    if len(set(rings[-1])) > 1:
        faces.append(tuple(rings[-1]))
    o = C.mesh_object(name, verts, faces, mat, smooth=smooth)
    C.recalc_normals(o)
    return o


def rounded_profile(pts, r, n=8):
    """Fillet the corners of an open lathe profile."""
    return fillet(pts, r, n=n, closed=False)


def tube(name, path, radius, mat, n=24, caps=True, up=None, flat=1.0, closed=False, cap_n=6):
    """Sweep a (possibly elliptical) circle along a 3D path. radius may be a list per point.
    flat scales the section along the second frame axis (ribbons)."""
    P = [Vector(p) for p in path]
    m = len(P)
    R = radius if isinstance(radius, (list, tuple)) else [radius] * m
    T = []
    for i in range(m):
        if closed:
            t = P[(i + 1) % m] - P[i - 1]
        else:
            t = P[min(i + 1, m - 1)] - P[max(i - 1, 0)]
        T.append(t.normalized())
    frames = []
    if up is not None:
        for t in T:
            u = Vector(up) - Vector(up).dot(t) * t
            nn = u.normalized()
            frames.append((nn, t.cross(nn)))
    else:
        ref = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
        nn = (ref - ref.dot(T[0]) * T[0]).normalized()
        for t in T:
            nn = (nn - nn.dot(t) * t).normalized()
            frames.append((nn, t.cross(nn)))
    verts, rings = [], []

    def ring_at(c, nn, bb, r, scale=1.0):
        idx = []
        for k in range(n):
            a = math.tau * k / n
            verts.append(c + nn * (math.cos(a) * r * scale) + bb * (math.sin(a) * r * scale * flat))
            idx.append(len(verts) - 1)
        return idx

    if caps and not closed:
        nn, bb = frames[0]
        for k in range(cap_n, 0, -1):
            phi = 0.5 * math.pi * k / cap_n
            if k == cap_n:
                verts.append(P[0] - T[0] * R[0] * math.sin(phi) * flat)
                rings.append([len(verts) - 1] * n)
            else:
                rings.append(ring_at(P[0] - T[0] * R[0] * math.sin(phi) * flat, nn, bb, R[0], math.cos(phi)))
    for i in range(m):
        nn, bb = frames[i]
        rings.append(ring_at(P[i], nn, bb, R[i]))
    if caps and not closed:
        nn, bb = frames[-1]
        for k in range(1, cap_n + 1):
            phi = 0.5 * math.pi * k / cap_n
            if k == cap_n:
                verts.append(P[-1] + T[-1] * R[-1] * math.sin(phi) * flat)
                rings.append([len(verts) - 1] * n)
            else:
                rings.append(ring_at(P[-1] + T[-1] * R[-1] * math.sin(phi) * flat, nn, bb, R[-1], math.cos(phi)))
    faces = []
    pairs = list(zip(rings, rings[1:]))
    if closed:
        pairs.append((rings[-1], rings[0]))
    for A, B in pairs:
        for k in range(n):
            j = (k + 1) % n
            f = []
            for v in (A[k], A[j], B[j], B[k]):
                if v not in f:
                    f.append(v)
            if len(f) >= 3:
                faces.append(tuple(f))
    if not caps and not closed:
        faces.append(tuple(reversed(rings[0])))
        faces.append(tuple(rings[-1]))
    o = C.mesh_object(name, [tuple(v) for v in verts], faces, mat, smooth=True)
    C.recalc_normals(o)
    return o


def sphere(name, r, center, mat, scale=(1, 1, 1), segs=48, rings=32):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + Vector(center)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    return smooth_all(o)


def subsurf(o, levels=2):
    s = o.modifiers.new("Sub", "SUBSURF")
    s.levels = levels
    s.render_levels = levels
    C.apply_modifiers(o)
    return smooth_all(o)


def boolean(o, cutters, op="DIFFERENCE"):
    for c in cutters:
        m = o.modifiers.new("B", "BOOLEAN")
        m.operation = op
        m.object = c
        m.solver = "EXACT"
    C.apply_modifiers(o)
    for c in cutters:
        bpy.data.objects.remove(c)
    return o


def xf(objs, loc=(0, 0, 0), rot=(0, 0, 0), scale=1.0):
    """Rotate (degrees, XYZ euler), scale, then move objects about the origin."""
    if not isinstance(objs, (list, tuple)):
        objs = [objs]
    s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
    mat = Matrix.Translation(loc) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4() @ Matrix.Diagonal((*s, 1.0))
    for o in objs:
        o.matrix_world = mat @ o.matrix_world
    return objs


def frame_on(o, origin, xaxis, normal):
    """Place a puff (built facing -Y) onto a plane: its 2D u along xaxis, front along normal."""
    x = Vector(xaxis).normalized()
    nrm = Vector(normal).normalized()
    z = nrm.cross(x).normalized()  # 2D v direction
    rot = Matrix((x, -nrm, z)).transposed().to_4x4()
    o.matrix_world = Matrix.Translation(origin) @ rot @ o.matrix_world
    return o


def pose(objs, yaw=0.0, pitch=0.0, roll=0.0):
    """Turn the finished model: yaw about Z, then pitch (top toward camera), then roll in the image plane."""
    m = (Matrix.Rotation(math.radians(roll), 4, "Y") @ Matrix.Rotation(math.radians(pitch), 4, "X")
         @ Matrix.Rotation(math.radians(yaw), 4, "Z"))
    for o in objs:
        o.matrix_world = m @ o.matrix_world
    return objs


# ----------------------------------------------------------------------------------------------
# icons (each returns a list of mesh objects)
# ----------------------------------------------------------------------------------------------

WHITE = (250, 250, 255)
DARK = (44, 34, 58)


def gold_mat():
    return M("Gold", (255, 204, 40), rough=0.26, metal=0.2, coat=0.5, edge=(238, 118, 14))


def steel_mat():
    return M("Steel", (196, 206, 224), rough=0.24, metal=0.35, coat=0.45, edge=(104, 116, 150))


def se_ring(z, hx, hy, p=4.0, n=64, cx=0.0, cy=0.0):
    pts = []
    for k in range(n):
        a = math.tau * k / n
        c, s = math.cos(a), math.sin(a)
        pts.append((cx + hx * math.copysign(abs(c) ** (2 / p), c), cy + hy * math.copysign(abs(s) ** (2 / p), s), z))
    return pts


def loft_rings(name, rings, mat, cap_start=True, cap_end=True, smooth=True):
    verts, idx = [], []
    for r in rings:
        idx.append(list(range(len(verts), len(verts) + len(r))))
        verts += [tuple(v) for v in r]
    o = C.mesh_object(name, verts, C.loft(idx, cap_start, cap_end), mat, smooth=smooth)
    C.recalc_normals(o)
    return o


def stroke_outline(loop, grow):
    """Offset a closed outline outward by `grow` (for decal borders)."""
    P = np.array(loop)
    t = np.roll(P, -1, axis=0) - np.roll(P, 1, axis=0)
    t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-12)
    nrm = np.stack([t[:, 1], -t[:, 0]], axis=1)
    area = 0.5 * np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])
    if area < 0:
        nrm = -nrm
    return [tuple(p) for p in P + nrm * grow]


def icon_coin():
    gold = gold_mat()
    hole = fillet(rect(0.6, 0.6), 0.08)

    def prof(d, V, dmax):
        edge = circ(d / 0.08)
        return (0.2 - 0.05 * smoothstep(0.15, 0.22, d)) * edge

    coin = puff("Coin", [circle(1.0, 200), list(reversed(hole))], gold, prof=prof, step=0.014)
    return pose([coin], yaw=32, pitch=8, roll=-12)


def crystal(name, h, r, mat, sides=6, cap=0.32):
    pts = [(0.0, -h * 0.1), (r * 0.62, 0.0), (r, h * 0.12), (r, h * 0.72), (r * cap, h), (0.0, h)]
    o = revolve(name, pts, mat, segs=sides, smooth=False)
    m = o.modifiers.new("Bevel", "BEVEL")
    m.width = r * 0.1
    m.segments = 2
    m.limit_method = "ANGLE"
    m.harden_normals = True
    C.apply_modifiers(o)
    return o


def icon_shard():
    cyan = M("Crystal", (40, 214, 255), rough=0.1, coat=0.6, emit=0.2, edge=(20, 120, 255))
    light = M("CrystalLight", (110, 236, 255), rough=0.1, coat=0.6, emit=0.2, edge=(30, 150, 255))
    mid = crystal("Mid", 2.2, 0.46, cyan)
    xf(mid, rot=(0, 0, 14), loc=(0, 0, -1.0))
    left = crystal("Left", 1.5, 0.34, light)
    xf(left, rot=(0, -34, 40), loc=(-0.2, -0.1, -0.95))
    right = crystal("Right", 1.3, 0.32, light)
    xf(right, rot=(0, 36, -20), loc=(0.2, -0.16, -0.95))
    return pose([mid, left, right], yaw=0, pitch=6)


def icon_shop():
    pink = M("Basket", (240, 40, 92), rough=0.3, coat=0.45, edge=(186, 14, 70))
    rimm = M("BasketRim", (255, 86, 126), rough=0.3, coat=0.45, edge=(214, 30, 84))
    steel = M("Handle", (176, 186, 206), rough=0.24, metal=0.3, coat=0.45, edge=(100, 110, 140))
    rings = [se_ring(-0.05, 0.58, 0.38), se_ring(0.0, 0.64, 0.44)]
    rings += [se_ring(z, 0.64 + 0.24 * z, 0.44 + 0.2 * z) for z in (0.2, 0.4, 0.6, 0.8, 1.0)]
    rings += [se_ring(1.0, 0.8, 0.56), se_ring(0.9, 0.78, 0.54), se_ring(0.12, 0.59, 0.39)]
    shell = loft_rings("Basket", rings, pink)
    cutters = []
    for zc in (0.33, 0.68):
        for x in (-0.46, -0.23, 0.0, 0.23, 0.46):
            cutters.append(rbox("CutF", (0.13, 2.0, 0.24), (x, 0, zc), 0.05, None))
        for y in (-0.24, 0.0, 0.24):
            cutters.append(rbox("CutS", (2.4, 0.13, 0.24), (0, y, zc), 0.05, None))
    cut = C.join(cutters, "Cutters")
    boolean(shell, [cut])
    shell.data.set_sharp_from_angle(angle=math.radians(50))
    rim = tube("Rim", se_ring(1.0, 0.84, 0.6), 0.085, rimm, n=20, closed=True)
    foot = tube("Foot", se_ring(0.0, 0.62, 0.42), 0.06, rimm, n=16, closed=True)
    hp = []
    lean = math.radians(40)
    for k in range(33):
        a = math.pi * k / 32
        x, z = -0.86 * math.cos(a), 0.78 * math.sin(a)
        hp.append((x, z * math.sin(lean), 1.0 + z * math.cos(lean)))
    handle = tube("Handle", hp, 0.075, steel, n=18)
    knobs = [sphere("Knob%d" % s, 0.11, (s * 0.88, 0, 1.0), steel) for s in (-1, 1)]
    return pose([shell, rim, foot, handle] + knobs, yaw=-20, pitch=22)


def icon_areas():
    red = M("Torii", (242, 56, 42), rough=0.3, coat=0.4, edge=(188, 20, 30))
    dark = M("ToriiDark", (62, 50, 78), rough=0.3, coat=0.45, edge=(30, 22, 44))
    gold = gold_mat()
    H = 1.95            # post height
    X = 0.7             # post offset
    objs = []
    for sx in (-1, 1):
        post = revolve("Post%d" % sx, rounded_profile([(0, 0), (0.18, 0), (0.155, H), (0, H)], 0.03), red, segs=40)
        xf(post, loc=(sx * X, 0, 0))
        foot = revolve("Foot%d" % sx, rounded_profile([(0, 0), (0.225, 0), (0.225, 0.26), (0, 0.26)], 0.06), dark, segs=40)
        xf(foot, loc=(sx * X, 0, -0.03))
        objs += [post, foot]
    nz, sz = H * 0.7, H - 0.07
    objs.append(rbox("Nuki", (2.1, 0.2, 0.22), (0, 0, nz), 0.06, red))
    objs.append(rbox("Shimaki", (2.36, 0.3, 0.2), (0, 0, sz), 0.06, red))
    objs.append(rbox("Strut", (0.18, 0.16, sz - nz), (0, 0, (sz + nz) / 2), 0.03, red))
    pz = (sz + nz) / 2
    plaque = puff("Plaque", [fillet(rect(0.34, 0.3), 0.05)], dark, thick=0.03, rim=0.03, wall=0.04)
    xf(plaque, loc=(0, -0.12, pz))
    frame = puff("PlaqueRim", [fillet(rect(0.44, 0.4), 0.08), list(reversed(fillet(rect(0.32, 0.28), 0.04)))], gold,
                 thick=0.03, rim=0.03, wall=0.05)
    xf(frame, loc=(0, -0.12, pz))
    objs += [plaque, frame]
    top, bot = [], []
    for k in range(41):
        t = -1 + 2 * k / 40
        top.append((1.46 * t, H + 0.4 + 0.2 * abs(t) ** 2.4))
        bot.append((1.32 * t, H + 0.03 + 0.15 * abs(t) ** 2.4))
    outline = bot + list(reversed(top))
    objs.append(puff("Kasagi", [fillet(outline, 0.08)], dark, thick=0.08, rim=0.08, wall=0.12, step=0.015))
    return pose(objs, yaw=30, pitch=6)


def icon_upgrade():
    green = M("Lime", (128, 232, 34), rough=0.3, coat=0.45, edge=(34, 158, 30))
    pts = [(-0.36, -1.0), (0.36, -1.0), (0.36, 0.04), (0.84, 0.04), (0, 1.0), (-0.84, 0.04), (-0.36, 0.04)]
    pts = fillet(pts, [0.13, 0.13, 0.08, 0.15, 0.18, 0.15, 0.08])
    o = puff("Arrow", [pts], green, thick=0.32, rim=0.32, soft=0.1)
    return pose([o], yaw=22, pitch=6)


def ellipse_pts(c, rx, ry, rot=0.0, n=64):
    return transform2d(circle(1.0, n, rx=rx, ry=ry), 1.0, rot, c)


def icon_pets():
    orange = M("PawOrange", (255, 140, 28), rough=0.3, coat=0.4, edge=(218, 76, 18))
    pink = M("PawPink", (255, 128, 172), rough=0.28, coat=0.45, edge=(228, 70, 128))
    pad = spline([(0, 0.2), (0.44, 0.08), (0.76, -0.3), (0.76, -0.7), (0.44, -0.92), (0, -0.84),
                  (-0.44, -0.92), (-0.76, -0.7), (-0.76, -0.3), (-0.44, 0.08)], per=10, closed=True)
    objs = [puff("Pad", [pad], orange, thick=0.3, rim=0.3, soft=0.1)]
    bean = transform2d(pad, 0.64, 0, (0, -0.1))
    b = puff("PadBean", [bean], pink, thick=0.1, rim=0.1, soft=0.06)
    xf(b, loc=(0, -0.22, -0.06))
    objs.append(b)
    for i, (c, rx, ry, rot) in enumerate([((-0.88, 0.34), 0.25, 0.31, 28), ((-0.33, 0.76), 0.27, 0.33, 8),
                                          ((0.33, 0.76), 0.27, 0.33, -8), ((0.88, 0.34), 0.25, 0.31, -28)]):
        objs.append(puff("Toe%d" % i, [ellipse_pts(c, rx, ry, rot)], orange, thick=0.26, rim=0.26, soft=0.06))
        tb = puff("Bean%d" % i, [ellipse_pts((c[0], c[1] - 0.02), rx * 0.6, ry * 0.6, rot)], pink, thick=0.08, rim=0.08, soft=0.04)
        xf(tb, loc=(0, -0.2, 0))
        objs.append(tb)
    return pose(objs, yaw=16, pitch=6, roll=-10)


def icon_inventory():
    wood = M("Wood", (200, 110, 50), rough=0.38, coat=0.25, edge=(136, 60, 26))
    groove = M("WoodGroove", (104, 48, 22), rough=0.5, coat=0.1)
    gold = gold_mat()
    dark = M("Keyhole", DARK, rough=0.4, coat=0.2)
    W, D = 1.9, 1.2
    objs = [rbox("Base", (W, D, 0.9), (0, 0, -0.4), 0.08, wood)]
    arc = [(0.6 * math.cos(a), 0.52 * math.sin(a)) for a in np.linspace(0, math.pi, 48)[1:-1]]
    lid_outline = [(-0.6, 0.0), (0.6, 0.0)] + arc
    lid = puff("Lid", [fillet(lid_outline, 0.06)], wood, thick=0.08, rim=0.08, wall=W / 2 - 0.08, step=0.02)
    xf(lid, rot=(0, 0, 90), loc=(0, 0, 0.07))
    objs.append(lid)
    for sx in (-1, 1):
        objs.append(rbox("Strap%d" % sx, (0.22, D + 0.05, 0.93), (sx * 0.6, 0, -0.4), 0.05, gold))
        st = puff("LidStrap%d" % sx, [fillet(stroke_outline(lid_outline, 0.035), 0.06)], gold, thick=0.035, rim=0.035, wall=0.075, step=0.02)
        xf(st, rot=(0, 0, 90), loc=(sx * 0.6, 0, 0.07))
        objs.append(st)
    objs.append(rbox("TrimTop", (W + 0.04, D + 0.04, 0.12), (0, 0, 0.02), 0.04, gold))
    objs.append(rbox("TrimBot", (W + 0.04, D + 0.04, 0.12), (0, 0, -0.8), 0.04, gold))
    for z in (-0.4,):
        g = rbox("Groove", (W - 0.1, D + 0.02, 0.03), (0, 0, z), 0.01, groove)
        objs.append(g)
    plate = [(-0.23, 0.26), (0.23, 0.26), (0.23, -0.1), (0, -0.3), (-0.23, -0.1)]
    lp = puff("LockPlate", [fillet(plate, 0.07)], gold, thick=0.04, rim=0.04, wall=0.03)
    xf(lp, loc=(0, -D / 2 - 0.05, -0.02))
    kh1 = puff("KeyholeA", [circle(0.065, 32, c=(0, 0.06))], dark, thick=0.02, rim=0.02)
    kh2 = puff("KeyholeB", [fillet([(-0.035, 0.04), (0.035, 0.04), (0.055, -0.14), (-0.055, -0.14)], 0.015)], dark, thick=0.02, rim=0.02)
    for k in (kh1, kh2):
        xf(k, loc=(0, -D / 2 - 0.115, -0.02))
    objs += [lp, kh1, kh2]
    return pose(objs, yaw=-28, pitch=14)


def arc_arrow(a_tail, a_tip, r_in, r_out, he, head_deg=36, n=48):
    """Outline of a thick circular arrow running clockwise from a_tail to a_tip (degrees)."""
    a_hb = a_tip + head_deg
    pts = []
    for k in range(n + 1):
        a = math.radians(a_tail + (a_hb - a_tail) * k / n)
        pts.append((r_out * math.cos(a), r_out * math.sin(a)))
    ahb, atip, rm = math.radians(a_hb), math.radians(a_tip), (r_in + r_out) / 2
    pts.append(((r_out + he) * math.cos(ahb), (r_out + he) * math.sin(ahb)))
    pts.append((rm * math.cos(atip), rm * math.sin(atip)))
    pts.append(((r_in - he) * math.cos(ahb), (r_in - he) * math.sin(ahb)))
    for k in range(n + 1):
        a = math.radians(a_hb + (a_tail - a_hb) * k / n)
        pts.append((r_in * math.cos(a), r_in * math.sin(a)))
    return fillet(pts, 0.07)


def icon_rebirth():
    purple = M("RebirthPurple", (170, 72, 255), rough=0.28, coat=0.5, edge=(104, 28, 214))
    white = M("RebirthWhite", (250, 250, 255), rough=0.28, coat=0.5, edge=(140, 172, 255))
    a = puff("ArrowA", [arc_arrow(196, 26, 0.52, 0.94, 0.3, head_deg=46)], purple, thick=0.24, rim=0.22, soft=0.1)
    b = puff("ArrowB", [arc_arrow(16, -154, 0.52, 0.94, 0.3, head_deg=46)], white, thick=0.24, rim=0.22, soft=0.1)
    return pose([a, b], yaw=14, pitch=14, roll=-4)


def icon_heart():
    t = np.linspace(0, math.tau, 240, endpoint=False)
    x = 16 * np.sin(t) ** 3
    y = 13 * np.cos(t) - 5 * np.cos(2 * t) - 2 * np.cos(3 * t) - np.cos(4 * t)
    pts = fillet([(a / 16, b / 16) for a, b in zip(x, y)], 0.12)
    red = M("HeartRed", (244, 36, 66), rough=0.28, coat=0.5, edge=(190, 10, 60))
    o = puff("Heart", [pts], red, thick=0.38, rim=0.75, soft=0.1)
    return pose([o], yaw=18, pitch=4, roll=-8)


def icon_star():
    pts = fillet(star_pts(5, 1.0, 0.5), [0.16, 0.1] * 5)
    gold = M("StarGold", (255, 206, 40), rough=0.26, metal=0.2, coat=0.5, edge=(238, 118, 14))
    o = puff("Star", [pts], gold, thick=0.34, rim=0.45, soft=0.1)
    return pose([o], yaw=16, pitch=4, roll=-6)


def question_mark(scale=1.0):
    """2D outlines of a chunky question mark: (hook, dot)."""
    arc = []
    for k in range(40):
        a = math.radians(165 - 250 * k / 39)
        arc.append((0.3 * math.cos(a), 0.3 + 0.3 * math.sin(a)))
    ctrl = arc + [(0.0, -0.02), (0.0, -0.12)]
    path = spline(ctrl[::3] + ctrl[-2:], per=6)
    hook = stroke(path, 0.2)
    dot = circle(0.11, 40, c=(0.0, -0.4))
    return transform2d(hook, scale), transform2d(dot, scale)


def icon_mystery():
    gold = M("BlockGold", (255, 200, 40), rough=0.3, coat=0.45, edge=(240, 128, 16))
    white = M("BlockWhite", (255, 253, 242), rough=0.35, coat=0.3)
    rim = M("BlockRim", (232, 120, 20), rough=0.35, coat=0.3)
    s = 1.0
    objs = [rbox("Block", (2 * s, 2 * s, 2 * s), (0, 0, 0), 0.22, gold, segs=5)]
    faces = [((0, -s, 0), (1, 0, 0), (0, -1, 0)), ((s, 0, 0), (0, 1, 0), (1, 0, 0)), ((0, 0, s), (1, 0, 0), (0, 0, 1))]
    for fi, (c, xa, nrm) in enumerate(faces):
        hook, dot = question_mark(1.22)
        hook = transform2d(hook, 1.0, 0, (0.0, 0.06))
        dot = transform2d(dot, 1.0, 0, (0.0, 0.06))
        for li, shp in enumerate((hook, dot)):
            back = puff("QB%d%d" % (fi, li), [stroke_outline(shp, 0.055)], rim, thick=0.035, rim=0.035)
            front = puff("QF%d%d" % (fi, li), [shp], white, thick=0.05, rim=0.05)
            frame_on(back, Vector(c) + Vector(nrm) * 0.005, xa, nrm)
            frame_on(front, Vector(c) + Vector(nrm) * 0.03, xa, nrm)
            objs += [back, front]
        for (du, dv) in ((-0.68, -0.68), (0.68, -0.68), (-0.68, 0.68), (0.68, 0.68)):
            dotp = puff("Rv%d%d%d" % (fi, du > 0, dv > 0), [circle(0.075, 32, c=(du, dv))], white, thick=0.03, rim=0.03)
            frame_on(dotp, Vector(c) + Vector(nrm) * 0.005, xa, nrm)
            objs.append(dotp)
    return pose(objs, yaw=-38, pitch=18)


def icon_gift():
    purple = M("GiftPurple", (156, 64, 240), rough=0.3, coat=0.45, edge=(96, 30, 196))
    gold = M("Ribbon", (255, 196, 36), rough=0.26, coat=0.5, edge=(240, 122, 16))
    objs = [
        rbox("Box", (1.6, 1.6, 1.2), (0, 0, -0.12), 0.12, purple),
        rbox("Lid", (1.8, 1.8, 0.42), (0, 0, 0.64), 0.12, purple),
        rbox("RibA", (0.38, 1.64, 1.22), (0, 0, -0.12), 0.06, gold),
        rbox("RibB", (1.64, 0.38, 1.22), (0, 0, -0.12), 0.06, gold),
        rbox("RibC", (0.4, 1.84, 0.46), (0, 0, 0.64), 0.06, gold),
        rbox("RibD", (1.84, 0.4, 0.46), (0, 0, 0.64), 0.06, gold),
    ]
    top = 0.85
    for side in (-1, 1):
        ctrl = [(0.0, 0.0), (0.3, 0.36), (0.66, 0.66), (0.98, 0.56), (0.94, 0.16), (0.56, 0.02)]
        pts = [(side * x, 0.0, top + z) for (x, z) in spline(ctrl, per=8, closed=True)]
        loop = tube("Bow%d" % side, pts, 0.26, gold, n=24, closed=True, up=(0, 1, 0), flat=0.45)
        xf(loop, rot=(0, 0, side * 16))
        objs.append(loop)
        tail = tube("Tail%d" % side, [(side * 0.1, -0.05, top), (side * 0.34, -0.42, top - 0.04), (side * 0.5, -0.8, top - 0.02)],
                    0.2, gold, n=16, up=(0, 0, 1), flat=0.35)
        objs.append(tail)
    objs.append(sphere("Knot", 0.26, (0, 0, top + 0.08), gold, scale=(1.0, 0.9, 0.85)))
    return pose(objs, yaw=-30, pitch=12)


def conform(feat, target, lift=0.0):
    """Drape a flat decal built facing -Y onto the front of `target` (both in world space)."""
    bpy.context.view_layer.update()
    inv = target.matrix_world.inverted()
    mw = feat.matrix_world.copy()
    for v in feat.data.vertices:
        w = mw @ v.co
        o = inv @ Vector((w.x, -20.0, w.z))
        dvec = (inv.to_3x3() @ Vector((0, 1, 0))).normalized()
        ok, loc, _n, _i = target.ray_cast(o, dvec)
        if ok:
            hit = target.matrix_world @ loc
            w.y += hit.y - lift
            v.co = mw.inverted() @ w
    feat.data.update()
    return feat


def polyline_outline(pts, w):
    """Mitred outline of a thick open polyline (flat ends; fillet them for round caps)."""
    P = [Vector(p) for p in pts]
    n = len(P)
    L, R = [], []
    for i in range(n):
        if i == 0 or i == n - 1:
            t = (P[1] - P[0]) if i == 0 else (P[-1] - P[-2])
            t.normalize()
            nr = Vector((-t.y, t.x))
            L.append(P[i] + nr * w / 2)
            R.append(P[i] - nr * w / 2)
        else:
            t1, t2 = (P[i] - P[i - 1]).normalized(), (P[i + 1] - P[i]).normalized()
            n1, n2 = Vector((-t1.y, t1.x)), Vector((-t2.y, t2.x))
            m = (n1 + n2).normalized()
            ln = (w / 2) / max(m.dot(n1), 0.2)
            L.append(P[i] + m * ln)
            R.append(P[i] - m * ln)
    return [tuple(v) for v in R + L[::-1]]


def gear_pts(teeth, r_root, r_tip, top=0.44, base=0.66, n=6):
    pts = []
    half = math.pi / teeth
    for i in range(teeth):
        c = math.tau * i / teeth + math.pi / 2
        for k in range(n):
            a = c - half + (half - half * base) * k / n
            pts.append((r_root * math.cos(a), r_root * math.sin(a)))
        for k in range(n + 1):
            a = c - half * top + 2 * half * top * k / n
            pts.append((r_tip * math.cos(a), r_tip * math.sin(a)))
        for k in range(n):
            a = c + half * base + (half - half * base) * k / n
            pts.append((r_root * math.cos(a), r_root * math.sin(a)))
    return pts


def icon_trophy():
    gold = gold_mat()
    base = M("TrophyBase", (78, 56, 104), rough=0.3, coat=0.45, edge=(40, 26, 60))
    cream = M("TrophyStar", (255, 246, 196), rough=0.28, coat=0.5, edge=(250, 190, 60))
    prof = [(0, -0.72), (0.46, -0.72), (0.46, -0.6), (0.24, -0.5), (0.13, -0.32), (0.21, -0.22), (0.21, -0.13),
            (0.12, -0.05), (0.16, 0.05), (0.48, 0.2), (0.7, 0.48), (0.82, 0.82), (0.88, 1.1), (0.88, 1.19),
            (0.77, 1.19), (0.73, 0.9), (0.6, 0.56), (0.3, 0.4), (0, 0.36)]
    cup = revolve("Cup", rounded_profile(prof, 0.045), gold, segs=72)
    objs = [cup]
    for s in (-1, 1):
        path = spline([(0.74, 0, 1.0), (1.08, 0, 1.02), (1.24, 0, 0.78), (1.1, 0, 0.5), (0.64, 0, 0.34)], per=10)
        objs.append(tube("Handle%d" % s, [(s * x, y, z) for (x, y, z) in path], 0.085, gold, n=20))
    objs.append(rbox("Base1", (1.36, 1.0, 0.32), (0, 0, -1.02), 0.07, base))
    objs.append(rbox("Base2", (1.08, 0.82, 0.24), (0, 0, -0.76), 0.06, base))
    plate = puff("Plate", [fillet(rect(0.62, 0.16), 0.05)], gold, thick=0.02, rim=0.02, wall=0.015)
    xf(plate, loc=(0, -0.51, -1.02))
    star = puff("CupStar", [fillet(star_pts(5, 0.3, 0.15), [0.05, 0.03] * 5)], cream, thick=0.06, rim=0.06, soft=0.03)
    xf(star, loc=(0, 0, 0.72))
    conform(star, cup, lift=0.02)
    objs += [plate, star]
    return pose(objs, yaw=-8, pitch=10)


def ticket_outline(w=2.0, h=1.3, bites=3, br=0.13, r=0.12):
    x0, x1, y0, y1 = -w / 2, w / 2, -h / 2, h / 2
    pts = [(x0, y0), (x1, y0)]
    vs = [y0 + h * (i + 0.5) / bites for i in range(bites)]
    for v in vs:  # right edge, upward: semicircular bites into the ticket
        for k in range(13):
            a = -math.pi / 2 - math.pi * k / 12
            pts.append((x1 + br * math.cos(a), v + br * math.sin(a)))
    pts += [(x1, y1), (x0, y1)]
    for v in reversed(vs):  # left edge, downward
        for k in range(13):
            a = math.pi / 2 - math.pi * k / 12
            pts.append((x0 + br * math.cos(a), v + br * math.sin(a)))
    return fillet(pts, r)


def icon_codes():
    gold = M("Ticket", (255, 204, 40), rough=0.28, metal=0.15, coat=0.5, edge=(238, 118, 14))
    red = M("TicketStar", (255, 88, 52), rough=0.28, coat=0.5, edge=(210, 30, 40))

    def prof(d, V, dmax):
        return (0.14 - 0.045 * smoothstep(0.12, 0.17, d)) * circ(d / 0.07)

    t = puff("Ticket", [ticket_outline()], gold, prof=prof, step=0.014)
    star = puff("Star", [fillet(star_pts(5, 0.5, 0.25), [0.08, 0.05] * 5)], red, thick=0.09, rim=0.12, soft=0.05)
    xf(star, loc=(0, -0.08, 0))
    return pose([t, star], yaw=20, pitch=8, roll=14)


def icon_settings():
    steel = steel_mat()
    hubm = M("GearHub", (150, 162, 188), rough=0.24, metal=0.35, coat=0.45, edge=(80, 90, 120))
    body = puff("Gear", [fillet(gear_pts(8, 0.74, 1.0), 0.06), list(reversed(circle(0.3, 64)))], steel,
                thick=0.1, rim=0.1, wall=0.12, step=0.015)
    hub = puff("Hub", [circle(0.52, 96), list(reversed(circle(0.27, 64)))], hubm, thick=0.08, rim=0.08, wall=0.2, step=0.015)
    return pose([body, hub], yaw=24, pitch=12, roll=10)


def icon_egg():
    prof = []
    for k in range(41):
        t = math.pi * k / 40
        z = -math.cos(t)
        prof.append((0.78 * math.sin(t) * (1 - 0.13 * z), z * 1.02))
    prof[0] = (0.0, prof[0][1])
    prof[-1] = (0.0, prof[-1][1])

    def on_egg(z, phi):
        t = math.acos(-z / 1.02)
        r = 0.78 * math.sin(t) * (1 - 0.13 * (-math.cos(t)))
        return (r * math.cos(math.radians(phi)), r * math.sin(math.radians(phi)), z)

    teal, pink, orange, purple = (40, 196, 230), (255, 92, 150), (255, 150, 30), (150, 90, 255)
    spots = [(on_egg(0.5, -100), 0.2, teal), (on_egg(-0.05, -62), 0.24, pink), (on_egg(-0.15, -128), 0.17, orange),
             (on_egg(0.8, -55), 0.13, purple), (on_egg(-0.62, -90), 0.2, purple), (on_egg(0.25, -20), 0.18, orange),
             (on_egg(0.3, -160), 0.16, pink), (on_egg(-0.5, -30), 0.15, teal), (on_egg(-0.45, -150), 0.16, teal),
             (on_egg(0.9, -150), 0.11, pink), (on_egg(-0.2, 10), 0.15, purple), (on_egg(-0.2, 170), 0.15, purple)]
    mat = spot_material("EggShell", (255, 244, 218), spots, rough=0.32, coat=0.45)
    egg = revolve("Egg", prof, mat, segs=72)
    return pose([egg], yaw=0, pitch=4, roll=-14)


def two_tone_attr(o, name, fn):
    """Store fn(co) per vertex as a float attribute (drives crisp two-tone shading)."""
    a = o.data.attributes.new(name, "FLOAT", "POINT")
    for i, v in enumerate(o.data.vertices):
        a.data[i].value = fn(v.co)
    return o


def two_tone_material(name, col_a, col_b, attr, lo, hi, rough=0.24, metal=0.3, coat=0.5, edge_a=None, edge_b=None):
    mat = M(name, col_a, rough=rough, metal=metal, coat=coat)
    nt = mat.node_tree
    b = nt.nodes["Principled BSDF"]
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = attr
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = lo
    mr.inputs["From Max"].default_value = hi
    nt.links.new(at.outputs["Fac"], mr.inputs["Value"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = (*C.rgb(*col_a), 1)
    mix.inputs["B"].default_value = (*C.rgb(*col_b), 1)
    nt.links.new(mr.outputs["Result"], mix.inputs["Factor"])
    nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
    return mat


def icon_katana():
    blade_m = two_tone_material("Blade", (150, 166, 198), (238, 244, 255), "edge", 0.0, 0.03)
    gold = gold_mat()
    wrap = M("Wrap", (226, 38, 52), rough=0.36, coat=0.3, edge=(150, 14, 34))
    dark = M("Tsuka", (40, 30, 52), rough=0.4, coat=0.2)
    L0, L1 = -0.36, 1.5

    def curve(x):
        return 0.12 * ((x - L0) / (L1 - L0)) ** 2

    def width(x):
        return 0.54 - 0.08 * (x - L0) / (L1 - L0)

    bottom = [(x, -width(x) / 2 + curve(x)) for x in np.linspace(L0, 1.12, 30)]
    tip = spline([(1.12, -width(1.12) / 2 + curve(1.12)), (1.36, -0.14 + curve(1.36)), (1.54, 0.18 + curve(1.54))], per=8)[1:]
    top = [(x, width(x) / 2 + curve(x)) for x in np.linspace(1.36, L0, 30)]
    outline = fillet(bottom + tip + top, 0.04)
    blade = puff("Blade", [outline], blade_m, thick=0.08, rim=0.16, step=0.014)

    def edge_fn(co):
        return (-0.03 + 0.022 * math.sin(co.x * 11.0)) - (co.z - curve(co.x))

    two_tone_attr(blade, "edge", edge_fn)
    habaki = rbox("Habaki", (0.18, 0.26, 0.62), (L0 - 0.02, 0, 0), 0.05, gold)
    tsuba = puff("Tsuba", [fillet(rect(0.66, 1.0), 0.28)], gold, thick=0.05, rim=0.05, wall=0.06)
    xf(tsuba, rot=(0, 0, 90), loc=(L0 - 0.16, 0, 0.0))
    hx = np.linspace(L0 - 0.22, L0 - 1.08, 25)
    radii = [0.22 + 0.03 * abs(math.sin(math.pi * 3.5 * k / 24)) for k in range(25)]
    handle = tube("Handle", [(x, 0, 0) for x in hx], radii, wrap, n=28)
    pommel = sphere("Kashira", 0.24, (L0 - 1.12, 0, 0), gold, scale=(0.8, 1.0, 1.0))
    diamonds = []
    for k in range(4):
        x = L0 - 0.38 - 0.22 * k
        dm = puff("Dia%d" % k, [fillet([(0, -0.11), (0.075, 0), (0, 0.11), (-0.075, 0)], 0.025)], dark, thick=0.025, rim=0.025)
        xf(dm, loc=(x, -0.235, 0))
        diamonds.append(dm)
    objs = [blade, habaki, tsuba, handle, pommel] + diamonds
    xf(objs, rot=(0, -40, 0))
    return pose(objs, yaw=20, pitch=6)


def heart_pts(n=180, sharp=0.1):
    t = np.linspace(0, math.tau, n, endpoint=False)
    x = 16 * np.sin(t) ** 3
    y = 13 * np.cos(t) - 5 * np.cos(2 * t) - 2 * np.cos(3 * t) - np.cos(4 * t)
    return fillet([(a / 16, (b + 2.5) / 16) for a, b in zip(x, y)], sharp)


def icon_clover():
    leaf_m = M("Leaf", (86, 216, 62), rough=0.3, coat=0.4, edge=(20, 140, 44))
    stem_m = M("Stem", (66, 184, 54), rough=0.32, coat=0.35, edge=(20, 120, 40))
    objs = []
    for i, ang in enumerate((45, 135, 225, 315)):
        leaf = puff("Leaf%d" % i, [transform2d(heart_pts(sharp=0.08), 0.58, 0, (0, 0.53))], leaf_m, thick=0.2, rim=0.34, soft=0.07)
        xf(leaf, rot=(-10, 0, 0))                 # tip the outer lobes back a little
        xf(leaf, rot=(0, -(ang - 90), 0))
        objs.append(leaf)
    path = spline([(0.02, 0.1, -0.3), (0.1, 0.1, -0.8), (0.38, 0.1, -1.2)], per=10)
    objs.append(tube("Stem", path, [0.1] * len(path), stem_m, n=16))
    return pose(objs, yaw=16, pitch=10, roll=-6)


def icon_bolt():
    yellow = M("Bolt", (255, 224, 34), rough=0.28, coat=0.5, edge=(250, 136, 10))
    P = [(-0.05, 1.08), (0.66, 1.08), (0.22, 0.28), (0.7, 0.28), (-0.4, -1.12), (-0.12, -0.1), (-0.6, -0.1)]
    pts = fillet(P, [0.09, 0.09, 0.05, 0.1, 0.1, 0.05, 0.1])
    o = puff("Bolt", [pts], yellow, thick=0.28, rim=0.24, soft=0.08)
    return pose([o], yaw=20, pitch=6, roll=-4)


def keyhole(scale=1.0):
    head = circle(0.1 * scale, 40, c=(0, 0.06 * scale))
    stem = fillet([(-0.05 * scale, 0.04 * scale), (0.05 * scale, 0.04 * scale), (0.08 * scale, -0.22 * scale), (-0.08 * scale, -0.22 * scale)], 0.02 * scale)
    return head, stem


def icon_lock():
    gold = gold_mat()
    steel = steel_mat()
    dark = M("Keyhole", DARK, rough=0.4, coat=0.2)
    body = puff("Body", [fillet(rect(1.6, 1.28, (0, -0.4)), 0.24)], gold, thick=0.14, rim=0.14, wall=0.24, step=0.016)
    path = [(-0.5, 0, 0.0), (-0.5, 0, 0.62)] + [(-0.5 * math.cos(a), 0, 0.62 + 0.5 * math.sin(a)) for a in np.linspace(0, math.pi, 24)[1:-1]] + [(0.5, 0, 0.62), (0.5, 0, 0.0)]
    path = [path[0]] + spline(path, per=3)[1:]
    shackle = tube("Shackle", path, 0.15, steel, n=24)
    head, stem = keyhole(1.5)
    kh = [puff("KeyA", [transform2d(head, 1, 0, (0, -0.32))], dark, thick=0.03, rim=0.03),
          puff("KeyB", [transform2d(stem, 1, 0, (0, -0.32))], dark, thick=0.03, rim=0.03)]
    for k in kh:
        xf(k, loc=(0, -0.38, 0))
    return pose([body, shackle] + kh, yaw=20, pitch=8, roll=-6)


def icon_check():
    green = M("Check", (64, 214, 72), rough=0.28, coat=0.5, edge=(16, 146, 54))
    pts = polyline_outline([(-0.82, 0.12), (-0.3, -0.5), (0.86, 0.8)], 0.46)
    pts = fillet(pts, [0.22, 0.05, 0.22, 0.22, 0.14, 0.22])
    o = puff("Check", [pts], green, thick=0.28, rim=0.23, soft=0.08)
    return pose([o], yaw=18, pitch=6, roll=-4)


def icon_calendar():
    red = M("CalRed", (240, 50, 60), rough=0.3, coat=0.45, edge=(176, 16, 44))
    paper = M("Paper", (252, 252, 255), rough=0.36, coat=0.3, edge=(170, 186, 222))
    page2 = M("Paper2", (214, 224, 244), rough=0.4, coat=0.2, edge=(150, 164, 204))
    cell = M("CalCell", (196, 212, 240), rough=0.4, coat=0.2)
    steel = steel_mat()
    dark = M("CalHole", (90, 20, 40), rough=0.5, coat=0.1)
    back = puff("Back", [fillet(rect(1.8, 1.9, (0, -0.1)), 0.22)], page2, thick=0.06, rim=0.06, wall=0.05)
    xf(back, loc=(0.05, 0.12, -0.05))
    page = puff("Page", [fillet(rect(1.8, 1.9, (0, -0.1)), 0.22)], paper, thick=0.07, rim=0.07, wall=0.06)
    band = puff("Band", [fillet([(-0.9, 0.35), (0.9, 0.35), (0.9, 0.85), (-0.9, 0.85)], [0.02, 0.02, 0.22, 0.22])], red,
                thick=0.09, rim=0.09, wall=0.08)
    objs = [back, page, band]
    k = 0
    for r in range(3):
        for c in range(4):
            col = red if (r, c) == (1, 2) else cell
            sq = puff("Cell%d" % k, [fillet(rect(0.3, 0.26, (-0.54 + 0.36 * c, 0.02 - 0.33 * r)), 0.06)], col, thick=0.025, rim=0.025)
            xf(sq, loc=(0, -0.12, 0))
            objs.append(sq)
            k += 1
    for s in (-1, 1):
        hole = puff("Hole%d" % s, [circle(0.08, 32, c=(s * 0.45, 0.7))], dark, thick=0.02, rim=0.02)
        xf(hole, loc=(0, -0.16, 0))
        ring_pts = [(s * 0.45, 0.2 * math.cos(a) - 0.02, 0.86 + 0.24 * math.sin(a)) for a in np.linspace(0, math.tau, 48, endpoint=False)]
        ring = tube("Ring%d" % s, ring_pts, 0.065, steel, n=16, closed=True)
        objs += [hole, ring]
    return pose(objs, yaw=-16, pitch=10, roll=8)


def icon_oni():
    red = M("OniRed", (236, 46, 40), rough=0.32, coat=0.4, edge=(160, 12, 30))
    horn = M("Horn", (255, 238, 186), rough=0.32, coat=0.4, edge=(214, 160, 90))
    dark = M("OniDark", (46, 28, 54), rough=0.4, coat=0.3)
    yellow = M("OniEye", (255, 222, 40), rough=0.3, coat=0.5, edge=(240, 150, 20))
    mouth_m = M("OniMouth", (92, 16, 40), rough=0.4, coat=0.2)
    white = M("Fang", (255, 252, 244), rough=0.3, coat=0.5, edge=(200, 200, 220))
    face_pts = spline([(0, 0.98), (0.55, 0.9), (0.9, 0.5), (0.96, 0.0), (0.82, -0.52), (0.46, -0.9), (0, -1.0),
                       (-0.46, -0.9), (-0.82, -0.52), (-0.96, 0.0), (-0.9, 0.5), (-0.55, 0.9)], per=10, closed=True)
    face = puff("Face", [face_pts], red, thick=0.3, rim=0.5, dome=0.22, soft=0.1)
    objs = [face]
    for s in (-1, 1):
        path = spline([(s * 0.42, 0.05, 0.62), (s * 0.66, 0.05, 1.02), (s * 0.72, 0.05, 1.32), (s * 0.58, 0.05, 1.6)], per=8)
        n = len(path)
        radii = [0.24 * (1 - 0.8 * (k / (n - 1)) ** 1.2) + 0.02 for k in range(n)]
        objs.append(tube("Horn%d" % s, path, radii, horn, n=24))
        brow = puff("Brow%d" % s, [fillet([(s * 0.8, 0.46), (s * 0.12, 0.2), (s * 0.1, 0.4), (s * 0.72, 0.64)], 0.08)], dark, thick=0.06, rim=0.06)
        eye = puff("Eye%d" % s, [ellipse_pts((s * 0.38, 0.1), 0.2, 0.13, s * -14)], yellow, thick=0.05, rim=0.05)
        pupil = puff("Pupil%d" % s, [circle(0.065, 32, c=(s * 0.33, 0.08))], dark, thick=0.04, rim=0.04)
        objs += [brow, eye, pupil]
        conform(brow, face, lift=0.03)
        conform(eye, face, lift=0.015)
        conform(pupil, face, lift=0.05)
    nose = puff("Nose", [ellipse_pts((0, -0.2), 0.2, 0.13)], M("OniNose", (250, 80, 64), rough=0.3, coat=0.4, edge=(180, 30, 40)), thick=0.08, rim=0.1)
    conform(nose, face, lift=0.03)
    mouth = puff("Mouth", [spline([(-0.58, -0.44), (0, -0.52), (0.58, -0.44), (0.46, -0.74), (0, -0.84), (-0.46, -0.74)], per=8, closed=True)],
                 mouth_m, thick=0.03, rim=0.03)
    conform(mouth, face, lift=0.01)
    objs += [nose, mouth]
    for s in (-1, 1):
        fang = puff("Fang%d" % s, [fillet([(s * 0.46, -0.76), (s * 0.24, -0.72), (s * 0.4, -0.4)], 0.04)], white, thick=0.05, rim=0.05)
        conform(fang, face, lift=0.04)
        tooth = puff("Tooth%d" % s, [fillet([(s * 0.02, -0.5), (s * 0.2, -0.49), (s * 0.12, -0.62)], 0.03)], white, thick=0.04, rim=0.04)
        conform(tooth, face, lift=0.04)
        objs += [fang, tooth]
    return pose(objs, yaw=14, pitch=6)


def icon_shuriken():
    steel = steel_mat()
    darkm = M("ShuriDark", (92, 102, 132), rough=0.3, metal=0.3, coat=0.4, edge=(56, 62, 88))
    holem = M("ShuriHole", (40, 36, 60), rough=0.5, coat=0.1)
    outline = []  # (x, z, is_ridge)
    for i in range(4):
        a = math.radians(90 * i + 45)
        outline.append((math.cos(a), math.sin(a), True))
        for f, r in ((0.2, 0.74), (0.36, 0.55), (0.5, 0.44), (0.64, 0.55), (0.8, 0.74)):
            am = a + math.radians(90 * f)
            outline.append((r * math.cos(am), r * math.sin(am), f == 0.5))
    hc, e = 0.26, 0.05
    verts = [(0.0, -hc, 0.0), (0.0, hc, 0.0)]
    n = len(outline)
    for (x, z, _r) in outline:
        verts.append((x, -e, z))
    for (x, z, _r) in outline:
        verts.append((x, e, z))
    faces = []
    for k in range(n):
        j = (k + 1) % n
        faces.append((0, 2 + k, 2 + j))
        faces.append((1, 2 + n + j, 2 + n + k))
        faces.append((2 + k, 2 + n + k, 2 + n + j, 2 + j))
    o = C.mesh_object("Shuriken", verts, faces, steel, smooth=True)
    C.recalc_normals(o)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    ridge = {2 + k for k, p in enumerate(outline) if p[2]} | {2 + n + k for k, p in enumerate(outline) if p[2]}
    for ed in bm.edges:
        ids = {v.index for v in ed.verts}
        if ids & {0, 1} and ids & ridge:
            ed.smooth = False
        if all(i >= 2 for i in ids) and len(ed.link_faces) == 2 and any(len(f.verts) == 4 for f in ed.link_faces) and any(len(f.verts) == 3 for f in ed.link_faces):
            ed.smooth = False
    bm.to_mesh(o.data)
    bm.free()
    m = o.modifiers.new("Bevel", "BEVEL")
    m.width = 0.025
    m.segments = 3
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(20)
    m.harden_normals = True
    C.apply_modifiers(o)
    ring = puff("Ring", [circle(0.26, 64), list(reversed(circle(0.13, 48)))], darkm, thick=0.05, rim=0.05, wall=0.25)
    hole = puff("Hole", [circle(0.14, 48)], holem, thick=0.02, rim=0.02, wall=0.265)
    return pose([o, ring, hole], yaw=16, pitch=14, roll=6)


def icon_book():
    blue = M("BookBlue", (44, 124, 244), rough=0.3, coat=0.45, edge=(18, 58, 196))
    light = M("BookLabel", (132, 196, 255), rough=0.3, coat=0.4, edge=(70, 130, 240))
    line = M("BookLine", (64, 140, 246), rough=0.35, coat=0.3)
    pages = M("Pages", (255, 246, 224), rough=0.45, coat=0.2, edge=(214, 190, 150))
    ribbon = M("Bookmark", (240, 48, 64), rough=0.32, coat=0.4, edge=(170, 16, 40))
    # C-shaped cover seen from above: front board, rounded spine, back board
    c_pts = [(0.78, -0.3), (0.78, -0.2)] + [(-0.72 + 0.2 * math.cos(a), 0.2 * math.sin(a)) for a in np.linspace(-math.pi / 2, -3 * math.pi / 2, 24)]
    c_pts += [(0.78, 0.2), (0.78, 0.3)] + [(-0.72 + 0.3 * math.cos(a), 0.3 * math.sin(a)) for a in np.linspace(math.pi / 2, 3 * math.pi / 2, 24)]
    cover = puff("Cover", [fillet(c_pts, 0.035)], blue, thick=0.05, rim=0.05, wall=0.9, step=0.012)
    xf(cover, rot=(-90, 0, 0))
    block = rbox("Pages", (1.4, 0.4, 1.78), (0.04, 0, 0), 0.05, pages)
    label = puff("Label", [fillet(rect(0.9, 0.46, (0.05, 0.42)), 0.1)], light, thick=0.03, rim=0.03, wall=0.01)
    xf(label, loc=(0, -0.3, 0))
    lines = []
    for i, (w, z) in enumerate(((0.6, 0.5), (0.42, 0.34))):
        ln = puff("Line%d" % i, [fillet(rect(w, 0.07, (0.05, z)), 0.035)], line, thick=0.015, rim=0.015)
        xf(ln, loc=(0, -0.345, 0))
        lines.append(ln)
    rb = puff("Ribbon", [fillet([(0.3, -0.5), (0.5, -0.5), (0.5, -1.2), (0.4, -1.1), (0.3, -1.2)], 0.03)], ribbon, thick=0.03, rim=0.03, wall=0.01)
    xf(rb, loc=(0, -0.24, 0))
    return pose([cover, block, label, rb] + lines, yaw=-28, pitch=12, roll=6)


def icon_crown():
    gold = gold_mat()
    gem = M("Ruby", (240, 30, 64), rough=0.12, coat=0.7, edge=(150, 0, 40))
    velvet = M("Velvet", (196, 24, 60), rough=0.55, coat=0.1, edge=(110, 10, 40))
    R = 0.86
    U = math.tau * R
    period = U / 5
    pts = [(0.0, 0.0), (U, 0.0)]
    tips = []
    for i in range(5, 0, -1):
        u1 = period * i
        pts.append((u1, 0.52))
        pts.append((u1 - period / 2, 1.18))
        tips.append(u1 - period / 2)
    pts.append((0.0, 0.52))
    band = puff("Band", [fillet(pts, [0.0, 0.0] + [0.05, 0.1] * 5 + [0.0])], gold, thick=0.07, rim=0.07, wall=0.05, step=0.016)
    off = -math.pi / 2 - (period / 2) / R  # a tip at the front
    for v in band.data.vertices:
        u, y, z = v.co
        ang = u / R + off
        rad = R - y
        v.co = Vector((rad * math.cos(ang), rad * math.sin(ang), z))
    band.data.update()
    C.recalc_normals(band)
    objs = [band]
    for i, u in enumerate(tips):
        ang = u / R + off
        objs.append(sphere("Ball%d" % i, 0.12, ((R) * math.cos(ang), R * math.sin(ang), 1.22), gold))
    objs.append(tube("RimLow", [(R * math.cos(a), R * math.sin(a), 0.06) for a in np.linspace(0, math.tau, 96, endpoint=False)], 0.1, gold, n=16, closed=True))
    for i, da in enumerate((-40, 0, 40)):
        ang = -math.pi / 2 + math.radians(da)
        g = sphere("Gem%d" % i, 0.17, (0, 0, 0), gem, scale=(1.0, 0.6, 1.15) if da == 0 else (0.8, 0.55, 0.95), segs=10, rings=6)
        g.data.polygons.foreach_set("use_smooth", [False] * len(g.data.polygons))
        g.matrix_world = Matrix.Translation(((R + 0.1) * math.cos(ang), (R + 0.1) * math.sin(ang), 0.3)) @ Matrix.Rotation(ang + math.pi / 2, 4, "Z")
        objs.append(g)
    dome = revolve("Velvet", [(0, 0.66), (0.45, 0.6), (0.72, 0.42), (0.8, 0.22), (0.8, 0.1), (0, 0.1)], velvet, segs=64)
    objs.append(dome)
    return pose(objs, yaw=0, pitch=10)


def sparkle_pts(r, p=2.4, n=160):
    pts = []
    for k in range(n):
        t = math.tau * k / n
        c, s = math.cos(t), math.sin(t)
        pts.append((r * 0.82 * math.copysign(abs(c) ** p, c), r * math.copysign(abs(s) ** p, s)))
    return fillet(pts, 0.04 * r)


def icon_sparkle():
    yellow = M("SparkY", (255, 226, 56), rough=0.26, coat=0.5, emit=0.25, edge=(255, 148, 18))
    white = M("SparkW", (255, 255, 255), rough=0.26, coat=0.5, emit=0.2, edge=(170, 196, 255))
    objs = []
    for i, (c, r, m) in enumerate((((-0.2, -0.12), 1.0, yellow), ((0.72, 0.68), 0.46, white), ((0.8, -0.62), 0.32, white), ((-0.82, 0.78), 0.26, yellow))):
        o = puff("Spark%d" % i, [transform2d(sparkle_pts(r), 1.0, 0, c)], m, thick=0.2 * r + 0.05, rim=0.3 * r, soft=0.05 * r)
        objs.append(o)
    return pose(objs, yaw=14, pitch=6)


def icon_scroll():
    parch = M("Parchment", (252, 234, 186), rough=0.42, coat=0.2, edge=(224, 172, 100))
    wood = M("Roller", (180, 96, 46), rough=0.36, coat=0.35, edge=(118, 54, 24))
    gold = gold_mat()
    ink = M("Ink", (176, 120, 70), rough=0.5, coat=0.1)
    seal = M("Seal", (226, 40, 52), rough=0.3, coat=0.45, edge=(150, 10, 30))
    sheet = puff("Sheet", [rect(1.5, 1.8)], parch, thick=0.03, rim=0.03, wall=0.01)
    for v in sheet.data.vertices:
        v.co.y += 0.16 * (v.co.x / 0.75) ** 2 - 0.05 * math.sin(v.co.z * 2.2)
    sheet.data.update()
    objs = [sheet]
    for s in (-1, 1):
        z = s * 0.92
        yy = 0.02
        objs.append(tube("Roll%d" % s, [(x, yy, z) for x in np.linspace(-0.8, 0.8, 12)], 0.19, parch, n=32, caps=False))
        objs.append(tube("Rod%d" % s, [(x, yy, z) for x in np.linspace(-1.0, 1.0, 12)], 0.1, wood, n=24))
        for sx in (-1, 1):
            objs.append(sphere("Knob%d%d" % (s, sx), 0.15, (sx * 1.04, yy, z), gold, scale=(0.8, 1, 1)))
    for i, (w, z) in enumerate(((1.0, 0.5), (0.9, 0.24), (1.0, -0.02), (0.6, -0.28))):
        ln = puff("Text%d" % i, [fillet(rect(w, 0.1, (-0.5 + w / 2 - 0.0, z)), 0.05)], ink, thick=0.015, rim=0.015)
        xf(ln, loc=(0, -0.04, 0))
        conform(ln, sheet, lift=0.012)
        objs.append(ln)
    sl = puff("Seal", [circle(0.2, 48, c=(0.38, -0.5))], seal, thick=0.06, rim=0.06, soft=0.02)
    conform(sl, sheet, lift=0.05)
    objs.append(sl)
    return pose(objs, yaw=18, pitch=8, roll=-8)


def icon_trash():
    red = M("Bin", (238, 52, 62), rough=0.3, coat=0.45, edge=(168, 18, 44))
    darkr = M("BinDark", (190, 30, 50), rough=0.32, coat=0.4, edge=(120, 10, 34))
    n = 96
    rings = []
    zs = np.linspace(-1.0, 0.55, 18)
    for z in zs:
        r0 = 0.6 + 0.16 * (z + 1.0) / 1.55
        amp = 0.05 * smoothstep(-0.95, -0.8, z) * (1 - smoothstep(0.35, 0.5, z))
        ring = []
        for k in range(n):
            a = math.tau * k / n
            g = (0.5 + 0.5 * math.cos(10 * a)) ** 6
            r = r0 * (1 - amp * g)
            ring.append((r * math.cos(a), r * math.sin(a), z))
        rings.append(ring)
    body = loft_rings("Bin", rings, red)
    body = subsurf(body, 1)
    objs = [body]
    objs.append(tube("BinRim", [(0.78 * math.cos(a), 0.78 * math.sin(a), 0.56) for a in np.linspace(0, math.tau, 96, endpoint=False)], 0.08, red, n=16, closed=True))
    objs.append(tube("BinFoot", [(0.61 * math.cos(a), 0.61 * math.sin(a), -0.98) for a in np.linspace(0, math.tau, 96, endpoint=False)], 0.06, darkr, n=16, closed=True))
    lid = revolve("Lid", rounded_profile([(0, 0.62), (0.88, 0.62), (0.88, 0.72), (0.6, 0.86), (0, 0.9)], 0.05), red, segs=72)
    handle = tube("LidHandle", spline([(-0.28, 0, 0.84), (-0.24, 0, 1.08), (0.24, 0, 1.08), (0.28, 0, 0.84)], per=8), 0.075, darkr, n=16)
    objs += [lid, handle]
    return pose(objs, yaw=0, pitch=12, roll=-4)


def icon_potion():
    liquid = M("PotionPink", (255, 80, 186), rough=0.18, coat=0.7, emit=0.15, edge=(210, 20, 150))
    glass = M("Glass", (206, 234, 255), rough=0.08, coat=0.8, edge=(110, 168, 250), edge_amt=0.9)
    cork = M("Cork", (214, 150, 86), rough=0.5, coat=0.15, edge=(150, 90, 40))
    froth = M("Froth", (255, 170, 222), rough=0.2, coat=0.5, edge=(240, 100, 180))
    R, cz = 0.82, -0.32
    zl = cz + 0.3

    def sph(z):
        return math.sqrt(max(0.0, R * R - (z - cz) ** 2))

    low = [(0.0, cz - R)] + [(sph(z), z) for z in np.linspace(cz - R + 0.02, zl, 24)] + [(0.0, zl)]
    body = revolve("Liquid", low, liquid, segs=72)
    zt = cz + math.sqrt(R * R - 0.28 ** 2)
    up = [(0.0, zl)] + [(sph(z), z) for z in np.linspace(zl, zt, 16)] + [(0.28, zt + 0.05), (0.27, 0.72), (0.34, 0.76), (0.34, 0.86), (0.0, 0.86)]
    top = revolve("Glass", rounded_profile(up, 0.03), glass, segs=72)
    meniscus = tube("Froth", [(sph(zl) * math.cos(a), sph(zl) * math.sin(a), zl) for a in np.linspace(0, math.tau, 96, endpoint=False)], 0.05, froth, n=12, closed=True)
    ck = revolve("Cork", rounded_profile([(0, 0.7), (0.24, 0.7), (0.29, 1.12), (0, 1.12)], 0.06), cork, segs=48)
    bubbles = [sphere("Bub%d" % i, r, c, froth) for i, (r, c) in enumerate(((0.09, (-0.28, -0.72, -0.2)), (0.06, (-0.12, -0.78, -0.48)), (0.05, (-0.42, -0.62, -0.5))))]
    return pose([body, top, meniscus, ck] + bubbles, yaw=0, pitch=6, roll=-12)


def icon_boot():
    blue = M("Boot", (44, 146, 255), rough=0.3, coat=0.45, edge=(18, 70, 214))
    white = M("BootWhite", (252, 252, 255), rough=0.32, coat=0.4, edge=(160, 180, 240))
    yellow = M("BootStripe", (255, 214, 34), rough=0.3, coat=0.45, edge=(245, 130, 10))
    boot_pts = spline([(-0.62, 0.98), (0.14, 0.98), (0.2, 0.2), (0.5, 0.02), (0.9, -0.14), (1.04, -0.46), (0.9, -0.66),
                       (-0.62, -0.66), (-0.72, -0.3), (-0.66, 0.4)], per=10, closed=True)
    boot = puff("Boot", [boot_pts], blue, thick=0.3, rim=0.3, wall=0.08, soft=0.08)
    sole = puff("Sole", [fillet([(-0.76, -0.56), (1.02, -0.56), (1.1, -0.64), (1.0, -0.86), (-0.7, -0.86), (-0.8, -0.72)], 0.08)], white,
                thick=0.12, rim=0.12, wall=0.3)
    cuff = puff("Cuff", [fillet(rect(0.92, 0.24, (-0.24, 0.96)), 0.1)], white, thick=0.12, rim=0.12, wall=0.28)
    bolt = [(-0.05, 1.08), (0.66, 1.08), (0.22, 0.28), (0.7, 0.28), (-0.4, -1.12), (-0.12, -0.1), (-0.6, -0.1)]
    bolt = fillet(transform2d(bolt, 0.3, -62, (0.44, -0.3)), 0.025)
    stripe = puff("Stripe", [bolt], yellow, thick=0.05, rim=0.05)
    conform(stripe, boot, lift=0.02)
    wing_pts = spline([(-0.3, 0.3), (-0.5, 0.8), (-0.95, 1.08), (-1.35, 1.06), (-1.1, 0.84), (-1.4, 0.72), (-1.08, 0.54),
                       (-1.28, 0.38), (-0.84, 0.2)], per=10, closed=True)
    wing = puff("Wing", [wing_pts], white, thick=0.1, rim=0.12, soft=0.04)
    xf(wing, loc=(0, -0.3, 0))
    xf(wing, rot=(0, 0, -14))
    return pose([boot, sole, cuff, stripe, wing], yaw=16, pitch=8)


def icon_flame():
    red = M("FlameOut", (255, 86, 22), rough=0.3, coat=0.4, emit=0.3, edge=(226, 30, 20))
    orange = M("FlameMid", (255, 158, 26), rough=0.3, coat=0.4, emit=0.35, edge=(250, 90, 10))
    yellow = M("FlameIn", (255, 236, 96), rough=0.3, coat=0.4, emit=0.4, edge=(255, 180, 30))
    ctrl = [(0.0, -1.0), (0.64, -0.86), (0.92, -0.4), (0.86, 0.1), (0.68, 0.52), (0.5, 0.2), (0.3, 0.62), (0.08, 1.08),
            (-0.18, 0.62), (-0.34, 0.4), (-0.58, 0.66), (-0.84, 0.12), (-0.92, -0.4), (-0.64, -0.86)]
    outer = spline(ctrl, per=10, closed=True)
    objs = [puff("Outer", [outer], red, thick=0.3, rim=0.34, soft=0.08)]
    mid = transform2d(outer, 0.7, 0, (0.02, -0.26))
    o2 = puff("Mid", [mid], orange, thick=0.2, rim=0.24, soft=0.06)
    xf(o2, loc=(0, -0.16, 0))
    inn = transform2d(outer, 0.42, 0, (0.03, -0.5))
    o3 = puff("Inner", [inn], yellow, thick=0.14, rim=0.16, soft=0.04)
    xf(o3, loc=(0, -0.28, 0))
    return pose(objs + [o2, o3], yaw=12, pitch=4)


def buddy(prefix, mat, loc, scale=1.0):
    dark = M("BuddyEye", (36, 28, 48), rough=0.3, coat=0.5)
    white = M("BuddyShine", (255, 255, 255), rough=0.3, coat=0.3, emit=0.5)
    x, y, z = loc
    s = scale
    head = sphere(prefix + "Head", 0.5 * s, (x, y, z + 0.34 * s), mat, scale=(1.0, 0.94, 0.96))
    body = revolve(prefix + "Body", rounded_profile([(0, -0.62), (0.74, -0.62), (0.66, -0.2), (0.4, 0.0), (0, 0.04)], 0.14), mat, segs=64)
    xf(body, scale=(s, s * 0.8, s), loc=(x, y, z - 0.18 * s))
    objs = [head, body]
    for sx in (-1, 1):
        e = sphere(prefix + "Eye%d" % sx, 0.075 * s, (x + sx * 0.17 * s, y - 0.44 * s, z + 0.4 * s), dark, scale=(0.9, 0.6, 1.35))
        sh = sphere(prefix + "Shine%d" % sx, 0.025 * s, (x + sx * 0.17 * s + 0.02 * s, y - 0.5 * s, z + 0.45 * s), white)
        objs += [e, sh]
    smile = [(x + 0.16 * s * math.cos(a), y - 0.455 * s, z + 0.24 * s + 0.1 * s * math.sin(a)) for a in np.linspace(math.radians(200), math.radians(340), 12)]
    objs.append(tube(prefix + "Smile", smile, 0.03 * s, dark, n=12))
    return objs


def icon_friends():
    blue = M("FriendBlue", (60, 150, 255), rough=0.3, coat=0.45, edge=(20, 70, 214))
    green = M("FriendGreen", (72, 212, 88), rough=0.3, coat=0.45, edge=(20, 140, 56))
    objs = buddy("B", blue, (-0.5, 0.35, 0.18), 0.92) + buddy("G", green, (0.42, -0.3, -0.12), 1.0)
    return pose(objs, yaw=0, pitch=6)


def icon_clock():
    red = M("ClockRed", (240, 56, 60), rough=0.3, coat=0.45, edge=(170, 18, 44))
    face_m = M("ClockFace", (253, 253, 255), rough=0.34, coat=0.35, edge=(180, 196, 230))
    gold = gold_mat()
    dark = M("ClockHand", (40, 32, 56), rough=0.35, coat=0.4)
    body = puff("Body", [circle(0.86, 128)], red, thick=0.14, rim=0.14, wall=0.2, step=0.015)
    face = puff("Face", [circle(0.66, 128)], face_m, thick=0.03, rim=0.03, wall=0.02)
    xf(face, loc=(0, -0.3, 0))
    bezel = puff("Bezel", [circle(0.78, 128), list(reversed(circle(0.64, 128)))], red, thick=0.07, rim=0.07, wall=0.02)
    xf(bezel, loc=(0, -0.32, 0))
    objs = [body, face, bezel]
    for i in range(12):
        a = math.tau * i / 12
        r = 0.05 if i % 3 == 0 else 0.03
        t = puff("Tick%d" % i, [circle(r, 24, c=(0.52 * math.sin(a), 0.52 * math.cos(a)))], dark, thick=0.015, rim=0.015)
        xf(t, loc=(0, -0.345, 0))
        objs.append(t)
    for name, ang, ln, w in (("Hour", -58, 0.3, 0.1), ("Min", 58, 0.44, 0.08)):
        hand = puff(name, [stroke([(0, 0), (0, ln)], w)], dark, thick=0.02, rim=0.02)
        xf(hand, rot=(0, -ang, 0), loc=(0, -0.36, 0))
        objs.append(hand)
    cap = puff("Cap", [circle(0.08, 32)], red, thick=0.03, rim=0.03)
    xf(cap, loc=(0, -0.39, 0))
    objs.append(cap)
    for s in (-1, 1):
        bell = revolve("Bell%d" % s, rounded_profile([(0, 0.0), (0.36, 0.0), (0.34, 0.16), (0.2, 0.32), (0, 0.36)], 0.05), gold, segs=48)
        xf(bell, rot=(0, s * 38, 0), loc=(s * 0.56, 0, 0.72))
        leg = tube("Leg%d" % s, [(s * 0.46, 0, -0.62), (s * 0.66, 0, -0.98)], 0.08, gold, n=14)
        objs += [bell, leg]
    objs.append(tube("Hammer", [(0, 0, 0.8), (0, 0, 1.0)], 0.06, gold, n=12))
    objs.append(sphere("HammerKnob", 0.1, (0, 0, 1.04), gold))
    return pose(objs, yaw=-14, pitch=8, roll=6)


# ----------------------------------------------------------------------------------------------
# flat 2D sprites (Pillow / numpy, no outline)
# ----------------------------------------------------------------------------------------------

def _polar(size):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    c = (size - 1) / 2
    x, y = xx - c, c - yy
    return np.hypot(x, y) / (size / 2), np.arctan2(y, x)


def sprite_rays(size=ICON, ss=4):
    """White light burst: 12 wedge rays from the centre fading toward the edge (alpha ~0.9 centre)."""
    S = size * ss
    r, th = _polar(S)
    n = 12
    f = (th / math.tau * n) % 1.0                      # position within one ray period
    dist = np.abs(f - 0.5) * 2                          # 0 at ray centre, 1 at the gap centre
    ang_px = np.maximum(r * S / 2 * (math.tau / n), 1e-6)  # period width in pixels at this radius
    wedge = np.clip((0.5 - dist) * ang_px / 2.0 + 0.5, 0, 1)
    fade = np.clip(1 - r, 0, 1) ** 1.3
    core = np.exp(-(r / 0.12) ** 2)
    a = 0.9 * np.maximum(wedge * fade, core)
    a = np.clip(a, 0, 1)
    img = np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a])
    im = Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA")
    return downscale(im, size)


def sprite_glow(size=ICON, ss=4):
    """Soft round white glow: alpha 1 at the centre falling to 0 at the edge."""
    S = size * ss
    r, _ = _polar(S)
    a = np.clip(1 - r * r, 0, 1) ** 2
    img = np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a])
    im = Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA")
    return downscale(im, size)


SPRITES = {"Rays": sprite_rays, "Glow": sprite_glow}


ICONS = [
    ("Coin", icon_coin),
    ("Shard", icon_shard),
    ("Shop", icon_shop),
    ("Areas", icon_areas),
    ("Upgrade", icon_upgrade),
    ("Pets", icon_pets),
    ("Inventory", icon_inventory),
    ("Rebirth", icon_rebirth),
    ("Trophy", icon_trophy),
    ("Codes", icon_codes),
    ("Settings", icon_settings),
    ("Gift", icon_gift),
    ("Egg", icon_egg),
    ("Katana", icon_katana),
    ("Clover", icon_clover),
    ("Heart", icon_heart),
    ("Star", icon_star),
    ("Bolt", icon_bolt),
    ("Lock", icon_lock),
    ("Check", icon_check),
    ("Calendar", icon_calendar),
    ("Oni", icon_oni),
    ("Shuriken", icon_shuriken),
    ("Book", icon_book),
    ("Crown", icon_crown),
    ("Sparkle", icon_sparkle),
    ("Scroll", icon_scroll),
    ("Trash", icon_trash),
    ("Potion", icon_potion),
    ("Boot", icon_boot),
    ("Mystery", icon_mystery),
    ("Flame", icon_flame),
    ("Friends", icon_friends),
    ("Clock", icon_clock),
    ("Rays", None),     # flat sprite (SPRITES)
    ("Glow", None),     # flat sprite (SPRITES)
]
NAMES = [n for n, _ in ICONS]


# ----------------------------------------------------------------------------------------------
# scene, camera, lights, render
# ----------------------------------------------------------------------------------------------

def _world_points(objs):
    pts = []
    for o in objs:
        n = len(o.data.vertices)
        co = np.empty(n * 3)
        o.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        mw = np.array(o.matrix_world)
        pts.append(co @ mw[:3, :3].T + mw[:3, 3])
    return np.concatenate(pts)


def normalise(objs):
    """Centre the model and scale it so its largest extent is 2 units."""
    bpy.context.view_layer.update()
    P = _world_points(objs)
    lo, hi = P.min(0), P.max(0)
    s = 2.0 / max(hi - lo)
    c = (lo + hi) / 2
    m = Matrix.Diagonal((s, s, s, 1.0)) @ Matrix.Translation(Vector(-c))
    for o in objs:
        o.matrix_world = m @ o.matrix_world
    bpy.context.view_layer.update()


def setup_scene(objs):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.cycles.diffuse_bounces = 3
    scene.cycles.glossy_bounces = 3
    scene.cycles.transmission_bounces = 2
    scene.cycles.transparent_max_bounces = 4
    scene.render.resolution_x = scene.render.resolution_y = RENDER
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    world = bpy.data.worlds.new("IconWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.86, 0.9, 1.0, 1)
    bg.inputs[1].default_value = 0.38
    scene.world = world

    cam_data = bpy.data.cameras.new("IconCam")
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.sensor_width = 36.0
    cam = bpy.data.objects.new("IconCam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = CAM_DIR * CAM_DIST
    cam.rotation_euler = (-CAM_DIR).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    bpy.context.view_layer.update()
    # frame: fit the projected silhouette, leaving room for the outline
    P = _world_points(objs)
    inv = np.array(cam.matrix_world.inverted())
    pc = P @ inv[:3, :3].T + inv[:3, 3]
    tx = pc[:, 0] / -pc[:, 2]
    ty = pc[:, 1] / -pc[:, 2]
    fit = (FILL * RENDER - 2 * OUTLINE_PX) / RENDER
    span = max(tx.max() - tx.min(), ty.max() - ty.min())
    k = fit / span  # lens / sensor
    cam_data.lens = k * cam_data.sensor_width
    cam_data.shift_x = k * (tx.max() + tx.min()) / 2
    cam_data.shift_y = k * (ty.max() + ty.min()) / 2

    rig = [
        # name, direction from subject, power, size, colour
        ("Key", (-0.55, -0.62, 0.78), 900.0, 4.5, (1.0, 0.98, 0.95)),
        ("Fill", (0.95, -0.45, 0.05), 260.0, 6.0, (0.9, 0.95, 1.0)),
        ("Rim", (0.35, 0.85, 0.55), 520.0, 3.0, (1.0, 1.0, 1.0)),
    ]
    for name, d, power, size, col in rig:
        ld = bpy.data.lights.new(name, "AREA")
        ld.shape = "DISK"
        ld.size = size
        ld.energy = power
        ld.color = col
        lo = bpy.data.objects.new(name, ld)
        lo.location = Vector(d).normalized() * 8.0
        lo.rotation_euler = (-lo.location).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(lo)


def render_icon(name, builder):
    C.reset_scene()
    t0 = time.time()
    objs = builder()
    normalise(objs)
    setup_scene(objs)
    t1 = time.time()
    raw = os.path.join(SCRATCH, "raw", name + ".png")
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    bpy.context.scene.render.filepath = raw
    bpy.ops.render.render(write_still=True)
    t2 = time.time()
    finish(raw, name)
    t3 = time.time()
    return {"build": round(t1 - t0, 2), "render": round(t2 - t1, 2), "post": round(t3 - t2, 2), "total": round(t3 - t0, 2)}


# ----------------------------------------------------------------------------------------------
# post-processing
# ----------------------------------------------------------------------------------------------

def dilate(alpha, radius):
    """Anti-aliased grayscale dilation with a soft-edged disk."""
    H, W = alpha.shape
    r = int(math.ceil(radius + 0.5))
    pad = np.pad(alpha, r)
    out = np.zeros_like(alpha)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            w = min(1.0, max(0.0, radius + 0.5 - math.hypot(dx, dy)))
            if w <= 0:
                continue
            sh = pad[r + dy:r + dy + H, r + dx:r + dx + W]
            np.maximum(out, sh * w if w < 1 else sh, out=out)
    return out


def outline(img):
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3]
    ring = dilate(al, OUTLINE_PX)
    dark = np.array(OUTLINE_RGB, dtype=np.float32) / 255.0
    out_a = al + ring * (1 - al)
    out_rgb = (rgb * al[..., None] + dark * (ring * (1 - al))[..., None]) / np.maximum(out_a[..., None], 1e-6)
    res = np.dstack([out_rgb, out_a])
    return Image.fromarray(np.clip(res * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def downscale(img, size):
    return img.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")


def finish(raw, name):
    big = outline(Image.open(raw))
    os.makedirs(os.path.join(SCRATCH, "big"), exist_ok=True)
    big.save(os.path.join(SCRATCH, "big", name + ".png"))
    os.makedirs(ICON_DIR, exist_ok=True)
    downscale(big, ICON).save(os.path.join(ICON_DIR, name + ".png"))


# ----------------------------------------------------------------------------------------------
# atlas, Lua, FBX, contact sheet
# ----------------------------------------------------------------------------------------------

def rects():
    return [((i % COLS) * CELL + 2, (i // COLS) * CELL + 2, ICON, ICON) for i in range(len(NAMES))]


def build_atlas():
    atlas = Image.new("RGBA", (ATLAS, ATLAS), (0, 0, 0, 0))
    missing = []
    for name, (x, y, w, h) in zip(NAMES, rects()):
        p = os.path.join(ICON_DIR, name + ".png")
        if not os.path.exists(p):
            missing.append(name)
            continue
        im = Image.open(p).convert("RGBA")
        if im.size != (w, h):
            im = downscale(im, w)
        atlas.paste(im, (x, y))
    atlas.save(ATLAS_PATH)
    return missing


def write_lua():
    lines = [
        "-- Generated by tools/blender/icons.py: pixel rects (x, y, width, height) of each icon in UIIcons.png.",
        "return {",
        "\tSize = Vector2.new(%d, %d)," % (ATLAS, ATLAS),
        "\tIcons = {",
    ]
    for name, (x, y, w, h) in zip(NAMES, rects()):
        lines.append("\t\t%s = { %d, %d, %d, %d }," % (name, x, y, w, h))
    lines += ["\t},", "}"]
    os.makedirs(os.path.dirname(LUA_PATH), exist_ok=True)
    with open(LUA_PATH, "w") as f:
        f.write("\n".join(lines) + "\n")


def export_fbx():
    C.reset_scene()
    img = bpy.data.images.load(ATLAS_PATH)
    mat = bpy.data.materials.new("UIIconAtlas")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    # plate: 1 x 1 stud, 0.02 thick (Blender X x Z, thin along Y)
    w, t = 0.5, 0.01
    verts = [(x, y, z) for x in (-w, w) for y in (-t, t) for z in (-w, w)]
    # index = xi*4 + yi*2 + zi
    faces = [
        (1, 3, 7, 5),  # +Z top
        (0, 4, 6, 2),  # -Z bottom
        (0, 1, 5, 4),  # -Y  (faces Blender front view)
        (2, 6, 7, 3),  # +Y  (Roblox front, -Z)
        (0, 2, 3, 1),  # -X
        (4, 5, 7, 6),  # +X
    ]
    o = C.mesh_object("UIIconAtlas", verts, faces, mat)
    C.recalc_normals(o)
    uv = o.data.uv_layers.new(name="UVMap")
    corner = (0.001, 0.999)
    for poly in o.data.polygons:
        n = poly.normal
        for li in poly.loop_indices:
            v = o.data.vertices[o.data.loops[li].vertex_index].co
            if abs(n.y) > 0.5:
                # whole atlas, reading correctly when looking at this face from outside
                u = (v.x / (2 * w) + 0.5) if n.y < 0 else (0.5 - v.x / (2 * w))
                uv.data[li].uv = (u, v.z / (2 * w) + 0.5)
            else:
                uv.data[li].uv = corner
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.fbx(
        filepath=FBX_PATH, use_selection=True, object_types={"MESH"}, apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", bake_space_transform=True,
        use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False,
        path_mode="COPY", embed_textures=True,
    )
    return verify_fbx()


def verify_fbx():
    C.reset_scene()
    bpy.ops.import_scene.fbx(filepath=FBX_PATH)
    objs = [o.name for o in bpy.context.scene.objects if o.type == "MESH"]
    packed = []
    for im in bpy.data.images:
        pf = im.packed_file
        packed.append((im.name, pf.size if pf else 0, tuple(im.size)))
    fbx_size = os.path.getsize(FBX_PATH)
    png_size = os.path.getsize(ATLAS_PATH)
    ok = any(p[1] > 0 for p in packed) and fbx_size > png_size
    return {"objects": objs, "images": packed, "fbx_bytes": fbx_size, "png_bytes": png_size, "embedded": ok}


def _font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def contact_sheet():
    cw, ch = 250, 214
    pad = 20
    head = 44
    sec_h = head + 6 * ch + pad
    W = COLS * cw + 2 * pad
    H = 2 * sec_h + pad
    sheet = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    grey = Image.new("RGBA", (W, sec_h), (128, 128, 132, 255))
    sheet.paste(grey, (0, 0))
    g = np.zeros((sec_h, W, 4), dtype=np.uint8)
    yy, xx = np.mgrid[0:sec_h, 0:W]
    t = (xx / W * 0.6 + yy / sec_h * 0.4)[..., None]
    c0 = np.array([40, 200, 255], dtype=np.float32)
    c1 = np.array([60, 230, 140], dtype=np.float32)
    g[..., :3] = (c0 * (1 - t) + c1 * t).astype(np.uint8)
    g[..., 3] = 255
    sheet.paste(Image.fromarray(g, "RGBA"), (0, sec_h))
    draw = ImageDraw.Draw(sheet)
    f_title, f_name = _font(24), _font(17)
    for s, label in enumerate(("Mid-grey background", "Blue-green gradient background")):
        oy = s * sec_h
        draw.text((pad, oy + 10), label + "  (166 px and 48 px)", font=f_title, fill=(255, 255, 255, 255))
        for i, name in enumerate(NAMES):
            p = os.path.join(ICON_DIR, name + ".png")
            x = pad + (i % COLS) * cw
            y = oy + head + (i // COLS) * ch
            if os.path.exists(p):
                im = Image.open(p).convert("RGBA")
                sheet.alpha_composite(im, (x, y))
                sheet.alpha_composite(downscale(im, 48), (x + 176, y + 60))
            draw.text((x + 4, y + 170), "%d %s" % (i + 1, name), font=f_name, fill=(255, 255, 255, 255),
                      stroke_width=2, stroke_fill=(26, 22, 40, 255))
    os.makedirs(os.path.dirname(SHEET_PATH), exist_ok=True)
    sheet.convert("RGB").save(SHEET_PATH)


def pack():
    missing = build_atlas()
    write_lua()
    contact_sheet()
    info = export_fbx()
    return missing, info


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    only_pack = "--pack" in argv
    todo = []
    if not only_pack:
        want = args or NAMES
        unknown = [n for n in want if n not in NAMES]
        if unknown:
            sys.exit("unknown icon(s): %s (known: %s)" % (", ".join(unknown), ", ".join(NAMES)))
        todo = [(n, b) for n, b in ICONS if n in want]
    tpath = os.path.join(SCRATCH, "timings.json")
    try:
        with open(tpath) as f:
            timings = json.load(f)
    except (OSError, ValueError):
        timings = {}
    for name, builder in todo:
        if name in SPRITES:
            t0 = time.time()
            os.makedirs(ICON_DIR, exist_ok=True)
            SPRITES[name]().save(os.path.join(ICON_DIR, name + ".png"))
            tm = {"build": 0.0, "render": 0.0, "post": round(time.time() - t0, 2), "total": round(time.time() - t0, 2)}
        elif builder is None:
            print("skip %s (no model yet)" % name)
            continue
        else:
            tm = render_icon(name, builder)
        timings[name] = tm
        print("icon %-10s build %5.1fs  render %5.1fs  post %4.1fs" % (name, tm["build"], tm["render"], tm["post"]), flush=True)
        os.makedirs(SCRATCH, exist_ok=True)
        with open(tpath, "w") as f:
            json.dump(timings, f, indent=1)
    missing, info = pack()
    if missing:
        print("missing icons (left blank in atlas):", ", ".join(missing))
    print("atlas:", ATLAS_PATH)
    print("lua:", LUA_PATH)
    print("sheet:", SHEET_PATH)
    print("fbx:", FBX_PATH, info)


if __name__ == "__main__":
    main(sys.argv[1:])
