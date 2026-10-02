"""Building blocks for the hero katanas past the first three (hero_katana_designs.py).

Same frame as hero_katanas.py: grip middle at the origin, blade along Blender +Y,
cutting edge at -Z, spine at +Z, flat faces +-X. Everything a sword is made of goes
into a `Sword` (body parts, baked into one texture) or its glow list (neon pieces,
exported as HeroKatana_<id>__Glow, shown in the sword's Gem colour in game).

Blade outlines are two polylines in the (y, z) plane, edge and spine, from the base to
the tip; that is what gives each blade its own silhouette (serrated, flame, hooked,
cleaver, crystal...). Decals and glow inlays are placed in the same unbent (y, z)
coordinates, then the blade and everything on it are bent together.
"""
import math
import os

import bpy  # noqa: F401  (loads mathutils)
from mathutils import Vector

import common as C
import hero as H
import patterns as P

GOLD = (240, 186, 52)
SILVER = (200, 204, 214)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(int(round(lerp(a, b, t))) for a, b in zip(c1, c2))


def shade(c, k):
    return tuple(max(0, min(255, int(round(v * k)))) for v in c)


def interp(poly, y):
    """z of a y-monotonic polyline [(y, z)] at y."""
    if y <= poly[0][0]:
        return poly[0][1]
    for (ya, za), (yb, zb) in zip(poly, poly[1:]):
        if ya <= y <= yb:
            if yb - ya < 1e-9:
                return zb
            return za + (zb - za) * (y - ya) / (yb - ya)
    return poly[-1][1]


def sym(half):
    """Full outline from the +Z half [(z, dy)], listed from (0, top) round to (0, bottom)."""
    return list(half) + [(-z, dy) for z, dy in reversed(half[1:-1])]


def fix_uv_aspect(objs):
    """smart_project's correct_aspect reads the active image node of the material: a tall
    decal image squashes the blade's atlas island. Point the active node at the BSDF."""
    for o in objs:
        for m in o.data.materials:
            if m and m.use_nodes:
                b = m.node_tree.nodes.get("Principled BSDF")
                if b:
                    m.node_tree.nodes.active = b


# ---------------------------------------------------------------- the sword
class Sword:
    def __init__(self, kid, glow_rgb, decal_dir, emission=0.9):
        self.kid = kid
        self.pre = kid
        self.parts, self.glow = [], []
        self.n = 0
        self.dir = decal_dir
        self.mats = {}
        self.glow_rgb = glow_rgb
        self.gm = H.paint(self.pre + "_GlowMat", glow_rgb, roughness=0.1, emission=emission, roblox="Neon") if glow_rgb else None
        self.base = self.tip = None

    def nm(self, s):
        self.n += 1
        return "%s_%s%d" % (self.pre, s, self.n)

    def save(self, tag, d):
        return d.save(os.path.join(self.dir, "%s_%s.png" % (self.kid, tag)))

    def add(self, o):
        self.parts.append(o)
        return o

    def addg(self, o):
        self.glow.append(o)
        return o

    def mat(self, rgb, noise=0.04, roughness=0.45, **kw):
        key = (rgb, noise, roughness, tuple(sorted(kw.items())))
        if key not in self.mats:
            self.mats[key] = H.paint(self.nm("Mat"), rgb, noise=noise, roughness=roughness, **kw)
        return self.mats[key]

    # ---------------- generic parts
    def box(self, size, center, rgb, bevel=0.02, paint=None, ppu=600, glow=False, **kw):
        """Bevelled box; `paint(d, w, h)` draws a decal on its +-X faces (u along Z, v along Y)."""
        if glow:
            return self.addg(C.box(self.nm("GBox"), size, center, self.gm, bevel=bevel))
        if paint is None:
            return self.add(C.box(self.nm("Box"), size, center, self.mat(rgb, **kw), bevel=bevel))
        w, h = max(16, int(size[2] * ppu)), max(16, int(size[1] * ppu))
        d = P.Decal(w, h)
        paint(d, w, h)
        name = self.nm("DBox")
        m = H.decal_paint(name + "Mat", rgb, self.save(name, d), noise=kw.pop("noise", 0.04), roughness=kw.pop("roughness", 0.45), **kw)
        o = C.box(name, size, center, m, bevel=bevel)
        return self.add(H.planar_decal_uv(o, 2, 1))

    def plate(self, outline, yc, thick, rgb, paint=None, bevel=0.02, x=0.0, ppu=520, glow=False, zc=0.0, **kw):
        """Outline [(z, dy)] in the YZ plane extruded along X by `thick`, centred on (x, yc, zc).
        `paint(d, gx, gy)` draws on the flat faces (gx(z), gy(dy) map to decal pixels)."""
        pts = [(yc + dy, zc + z) for z, dy in outline]
        if glow:
            o = C.extrude_outline(self.nm("GPlate"), pts, thick, self.gm, axis="X", bevel=bevel)
            if x:
                o.location.x = x
                C.apply_transforms([o])
            return self.addg(o)
        zs = [p[0] for p in outline]
        ds = [p[1] for p in outline]
        z0, z1, d0, d1 = min(zs), max(zs), min(ds), max(ds)
        name = self.nm("Plate")
        if paint is not None:
            W, Hh = max(16, int((z1 - z0) * ppu)), max(16, int((d1 - d0) * ppu))
            d = P.Decal(W, Hh)
            paint(d, lambda z: (z - z0) / (z1 - z0) * W, lambda dy: (d1 - dy) / (d1 - d0) * Hh)
            m = H.decal_paint(name + "Mat", rgb, self.save(name, d), noise=kw.pop("noise", 0.04), roughness=kw.pop("roughness", 0.45), **kw)
        else:
            m = self.mat(rgb, **kw)
        o = C.extrude_outline(name, pts, thick, m, axis="X", bevel=bevel)
        if x:
            o.location.x = x
            C.apply_transforms([o])
        if paint is not None:
            # decal spans the outline itself (bevels can push the bounds a little)
            def fn(c):
                return ((c.z - zc - z0) / (z1 - z0), (c.y - yc - d0) / (d1 - d0))
            H.set_decal_uv(o, fn)
        return self.add(o)

    def ring(self, yc, r_in, r_out, thick, rgb=None, seg=28, paint=None, x=0.0, zc=0.0, glow=False, bevel=0.015, ppu=520, a0=0.0, **kw):
        """Annulus in the YZ plane (axis X): ring guards, halos, ring pommels."""
        name = self.nm("GRing" if glow else "Ring")
        verts = []
        for r, xx in ((r_out, -thick / 2), (r_out, thick / 2), (r_in, thick / 2), (r_in, -thick / 2)):
            for i in range(seg):
                a = a0 + 2 * math.pi * i / seg
                verts.append((x + xx, yc + math.sin(a) * r, zc + math.cos(a) * r))
        faces = []
        for k in range(4):
            a, b = k * seg, ((k + 1) % 4) * seg
            for i in range(seg):
                j = (i + 1) % seg
                faces.append((a + i, a + j, b + j, b + i))
        if glow:
            mat = self.gm
        elif paint is not None:
            W = int(2 * r_out * ppu)
            d = P.Decal(W, W)
            paint(d, lambda z: (z / r_out + 1) / 2 * W, lambda dy: (1 - (dy / r_out + 1) / 2) * W)
            mat = H.decal_paint(name + "Mat", rgb, self.save(name, d), noise=kw.pop("noise", 0.04), roughness=kw.pop("roughness", 0.45), **kw)
        else:
            mat = self.mat(rgb, **kw)
        o = H.flat(name, verts, faces, mat)
        if bevel > 0:
            m = o.modifiers.new("Bevel", "BEVEL")
            m.width = bevel
            m.segments = 1
            m.limit_method = "ANGLE"
            C.apply_modifiers(o)
        if paint is not None and not glow:
            H.set_decal_uv(o, lambda c: (((c.z - zc) / r_out + 1) / 2, ((c.y - yc) / r_out + 1) / 2))
        return self.addg(o) if glow else self.add(o)

    def gem(self, center, r, x_half, segments=6, glow=True, rgb=None, dome=0.6, roll=None):
        """Faceted gem through a part, axis X (both flat faces show it)."""
        prof = [(0.001, -x_half - r * dome), (r * 0.62, -x_half), (r, -x_half * 0.6), (r, x_half * 0.6), (r * 0.62, x_half), (0.001, x_half + r * dome)]
        o = C.lathe(self.nm("Gem"), prof, segments, self.gm if glow else self.mat(rgb, roughness=0.3), axis="X", smooth=False)
        o.location = center
        o.rotation_euler = (roll if roll is not None else (math.pi / segments if segments == 6 else math.pi / 4), 0, 0)
        C.apply_transforms([o])
        return self.addg(o) if glow else self.add(o)

    def stud(self, center, r, x_half, rgb=GOLD, segments=4):
        return self.gem(center, r, x_half, segments, glow=False, rgb=rgb, dome=1.2)

    def setting(self, center, r, x_half, rgb=GOLD, segments=6):
        """Flat metal bezel behind a gem."""
        return self.gem(center, r, x_half, segments, glow=False, rgb=rgb, dome=0.05)

    def crystal(self, base, direction, length, radius, rgb=None, sides=6, tip=0.35, glow=True, flat_x=1.0, foot=0.75):
        """Prism with a pointed end from `base` along `direction` (shards, ice, spikes)."""
        dvec = Vector(direction).normalized()
        prof = [(radius * foot, 0.0), (radius, length * (1 - tip) * 0.25), (radius, length * (1 - tip)), (0.001, length)]
        name = self.nm("Crys")
        o = C.lathe(name, prof, sides, self.gm if glow else self.mat(rgb, roughness=0.3), axis="Y", smooth=False)
        if flat_x != 1.0:
            for v in o.data.vertices:
                v.co.x *= flat_x
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = Vector((0, 1, 0)).rotation_difference(dvec)
        o.location = base
        C.apply_transforms([o])
        return self.addg(o) if glow else self.add(o)

    def spike(self, base, direction, length, radius, rgb=None, glow=False, sides=4, flat_x=1.0):
        return self.crystal(base, direction, length, radius, rgb, sides=sides, tip=1.0, glow=glow, flat_x=flat_x, foot=1.0)

    def tube(self, pts, radius, rgb=None, sides=6, glow=False, taper=None):
        """Rope / horn / tassel strand through 3D points (radius tapers by `taper(t)`)."""
        verts, rings = [], []
        n = len(pts)
        for i, p in enumerate(pts):
            p = Vector(p)
            t = i / (n - 1)
            dvec = (Vector(pts[min(i + 1, n - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
            a = Vector((1, 0, 0)) if abs(dvec.x) < 0.9 else Vector((0, 0, 1))
            u = dvec.cross(a).normalized()
            w = dvec.cross(u).normalized()
            r = radius * (taper(t) if taper else 1.0)
            ring = []
            for k in range(sides):
                ang = 2 * math.pi * k / sides
                verts.append(tuple(p + (u * math.cos(ang) + w * math.sin(ang)) * max(r, 0.002)))
                ring.append(len(verts) - 1)
            rings.append(ring)
        o = H.flat(self.nm("Tube"), verts, C.loft(rings), self.gm if glow else self.mat(rgb, roughness=0.5))
        return self.addg(o) if glow else self.add(o)

    # ---------------- grip and pommels
    def core(self, y0, y1, bottom, top, rgb):
        v = []
        for (hx, hz), y in ((bottom, y0), (top, y1)):
            v += [(hx, y, hz), (-hx, y, hz), (-hx, y, -hz), (hx, y, -hz)]
        return self.add(H.flat(self.nm("Core"), v, C.loft([[0, 1, 2, 3], [4, 5, 6, 7]]), self.mat(rgb, noise=0.05)))

    def grip(self, y0, y1, hx, hz, core_rgb, wrap_rgb, style="straps", turns=None, width=None, thick=0.03):
        """Grip core with a wrap: "straps" (two crossing wide straps, diamond tsuka-ito)
        or "ribbon" (one tight + one loose ribbon, like the tide katana)."""
        self.core(y0, y1, (hx, hz), (hx * 0.96, hz * 0.94), core_rgb)
        L = y1 - y0
        wrap = self.mat(wrap_rgb, noise=0.06)
        if style == "straps":
            pitch = width * 1.75 if width else 0.34
            w = width or 0.2
            n = turns or (L - 0.12) / pitch
            for hand, phase in ((1, 0.0), (-1, 0.5)):
                self.add(H.rect_band(self.nm("Strap"), hx, hz, y0 + 0.06, n, pitch, w, thick, wrap, phase=phase, hand=hand,
                                     gap=0.002 if hand > 0 else thick - 0.002))
        else:
            w = width or 0.14
            for hand, phase, gap, pitch in ((1, 0.0, 0.003, w * 1.07), (-1, 0.35, 0.02, w * 2.1)):
                n = (L - 0.1) / pitch
                self.add(H.rect_band(self.nm("Rib"), hx, hz, y0 + 0.04, n, pitch, w, thick * 0.6, wrap, phase=phase, hand=hand, gap=gap))

    def tassel(self, top, rgb, length=0.75, lean=-0.25, cord_rgb=None, strands=7, glow_bead=True, bead_r=0.07):
        """Cord, knot bead and a flared tassel hanging from `top` toward -Y (leaning to Z)."""
        top = Vector(top)
        cord = cord_rgb or rgb
        p1 = top + Vector((0, -0.16, lean * 0.2))
        self.tube([top, top + Vector((0, -0.08, lean * 0.08)), p1], 0.03, cord, sides=6)
        if glow_bead and self.gm:
            self.gem(p1 + Vector((0, -0.04, 0)), bead_r, bead_r * 0.8, 6, glow=True, dome=0.8)
        else:
            self.gem(p1 + Vector((0, -0.04, 0)), bead_r, bead_r * 0.8, 6, glow=False, rgb=shade(rgb, 0.8), dome=0.8)
        knot = p1 + Vector((0, -0.14, lean * 0.05))
        self.add(C.lathe(self.nm("Knot"), [(0.001, 0.07), (0.06, 0.05), (0.075, 0.0), (0.06, -0.05), (0.001, -0.07)], 8,
                         self.mat(shade(rgb, 0.85), noise=0.08), axis="Y", smooth=False))
        self.parts[-1].location = knot
        C.apply_transforms([self.parts[-1]])
        # flared skirt plus a few hanging strands
        end = knot + Vector((0, -length, lean))
        dvec = (end - knot).normalized()
        skirt = C.lathe(self.nm("Skirt"), [(0.001, 0.0), (0.05, 0.0), (0.075, length * 0.35), (0.11, length * 0.85), (0.1, length * 0.92), (0.001, length * 0.9)],
                        10, self.mat(rgb, noise=0.1, streaks=0.3), axis="Y", smooth=False)
        skirt.rotation_mode = "QUATERNION"
        skirt.rotation_quaternion = Vector((0, 1, 0)).rotation_difference(dvec)
        skirt.location = knot + dvec * 0.04
        C.apply_transforms([skirt])
        self.add(skirt)
        # cord band round the skirt top
        band = C.lathe(self.nm("TBand"), [(0.062, 0.0), (0.064, 0.05), (0.001, 0.05)], 10, self.mat(cord, noise=0.04), axis="Y", smooth=False)
        band.rotation_mode = "QUATERNION"
        band.rotation_quaternion = skirt.rotation_quaternion
        band.location = knot + dvec * 0.09
        C.apply_transforms([band])
        self.add(band)

    def claws(self, y, z_half, rgb=GOLD, drop=0.22, w=0.2):
        for side in (-1, 1):
            c = C.box(self.nm("Claw"), (w, drop, 0.1), (0, y, side * z_half), self.mat(rgb, roughness=0.3), bevel=0.02)
            c.rotation_euler = (side * 0.35, 0, 0)
            C.apply_transforms([c])
            self.add(c)

    def done(self, sharp=25):
        INFO[self.kid] = (self.base, self.tip)
        return self.parts, self.glow, sharp


INFO = {}


# ---------------------------------------------------------------- blades
class Blade:
    """Blade lofted between an edge polyline and a spine polyline (both [(y, z)], y
    increasing from the base y0 to the tip). Cross-section: flat faces from the spine to
    a bevel line, then a bevel to a thin edge (like hero.blade). `kissaki` = y where the
    tip facet starts (the bevel then sweeps across the whole width).

    Paint with canvas()/px(); add glow with inlay()/slab()/edge_glow(); finish() bends
    the blade and everything on it, makes the material and registers base/tip."""

    def __init__(self, sw, edge, spine, thick=0.11, edge_t=0.012, bevel=0.12, spine_bevel=0.014, kissaki=None,
                 bend=None, ppu=330, step=0.18, tip_facet=0.9):
        self.sw = sw
        self.edge, self.spine = edge, spine
        self.y0 = edge[0][0]
        self.y1 = max(edge[-1][0], spine[-1][0])
        self.L = self.y1 - self.y0
        self.thick, self.edge_t, self.bevel, self.sbev = thick, edge_t, bevel, spine_bevel
        self.kissaki = kissaki
        self.tip_facet = tip_facet
        self.bend_fn = bend or (lambda s: 0.0)
        ys = sorted({round(y, 5) for y, _ in edge + spine})
        if kissaki is not None:
            ys += [kissaki, kissaki + 0.012]
        ys = sorted(set(ys))
        fill = []
        for a, b in zip(ys, ys[1:]):
            k = int((b - a) / step)
            fill += [a + (b - a) * (i + 1) / (k + 1) for i in range(k)]
        self.ys = sorted(set(ys + fill))
        self.rows = [self._row(y) for y in self.ys]
        allz = [z for _, z in edge + spine]
        self.zlo, self.zhi = min(allz) - 0.03, max(allz) + 0.03
        self.ppu = ppu
        self.W = max(64, int((self.zhi - self.zlo) * ppu))
        self.H = max(256, int(self.L * ppu))
        self.attached = []
        self.decal = P.Decal(self.W, self.H)
        self.obj = self._mesh()

    # -- geometry
    def _row(self, y):
        ze, zs = interp(self.edge, y), interp(self.spine, y)
        if zs - ze < 0.006:
            m = (ze + zs) / 2
            ze, zs = m - 0.003, m + 0.003
        w = zs - ze
        h = min(self.thick / 2, 0.006 + w * 0.42)
        if self.kissaki is not None and y > self.kissaki + 0.006:
            b = w * self.tip_facet
        else:
            b = min(self.bevel, w * 0.6)
        sb = min(self.sbev, w * 0.12)
        b = min(b, w - sb - 0.002)
        e = min(self.edge_t / 2, h * 0.5)
        return dict(y=y, ze=ze, zs=zs, h=h, b=b, sb=sb, e=e)

    def _mesh(self):
        verts, rings = [], []
        for r in self.rows:
            y, ze, zs, h, b, sb, e = r["y"], r["ze"], r["zs"], r["h"], r["b"], r["sb"], r["e"]
            zb = ze + b
            ring = [(h - sb, y, zs), (h, y, zs - sb), (h, y, zb), (e, y, ze), (-e, y, ze), (-h, y, zb), (-h, y, zs - sb), (-h + sb, y, zs)]
            rings.append(list(range(len(verts), len(verts) + 8)))
            verts += ring
        o = H.flat(self.sw.nm("Blade"), verts, C.loft(rings), None)
        zlo, zhi, y0, L = self.zlo, self.zhi, self.y0, self.L
        H.set_decal_uv(o, lambda c: ((c.z - zlo) / (zhi - zlo), (c.y - y0) / L))
        return o

    def at(self, y, key):
        """Interpolated row value at y (h, b, ze, zs...)."""
        rows = self.rows
        if y <= rows[0]["y"]:
            return rows[0][key]
        for a, b in zip(rows, rows[1:]):
            if a["y"] <= y <= b["y"]:
                t = (y - a["y"]) / max(b["y"] - a["y"], 1e-9)
                return lerp(a[key], b[key], t)
        return rows[-1][key]

    def flat(self, y, f):
        """z at fraction f across the flat face (0 = bevel line, 1 = spine)."""
        zb = self.at(y, "ze") + self.at(y, "b")
        zt = self.at(y, "zs") - self.at(y, "sb")
        return lerp(zb, zt, f)

    def full(self, y, f):
        """z at fraction f across the whole width (0 = edge, 1 = spine)."""
        return lerp(self.at(y, "ze"), self.at(y, "zs"), f)

    def ys_between(self, ya, yb, n=40):
        return [ya + (yb - ya) * i / n for i in range(n + 1)]

    # -- painting (pixel space of the blade decal)
    def px(self, y, z):
        return ((z - self.zlo) / (self.zhi - self.zlo) * self.W, (1 - (y - self.y0) / self.L) * self.H)

    def pline(self, pts):
        return [self.px(y, z) for y, z in pts]

    def band_poly(self, ya, yb, fa, fb, whole=False, n=40):
        """Polygon (pixels) between fractions fa..fb across the flat (or whole) width."""
        fn = self.full if whole else self.flat
        ys = self.ys_between(ya, yb, n)
        left = [self.px(y, fn(y, fa)) for y in ys]
        right = [self.px(y, fn(y, fb)) for y in reversed(ys)]
        return left + right

    def line(self, f, ya, yb, whole=False, n=40):
        fn = self.full if whole else self.flat
        return [(y, fn(y, f)) for y in self.ys_between(ya, yb, n)]

    def paint_bevel(self, rgb, ya=None, yb=None, alpha=255, inset=0.0):
        """Colour the cutting bevel (the polished edge band)."""
        ya = self.y0 if ya is None else ya
        yb = self.y1 if yb is None else yb
        ys = self.ys_between(ya, yb, 80)
        left = [self.px(y, self.at(y, "ze") - 0.03) for y in ys]
        right = [self.px(y, self.at(y, "ze") + self.at(y, "b") * (1 - inset)) for y in reversed(ys)]
        self.decal.fill([left + right], rgb, alpha=alpha, blur=1.0)

    # -- glow pieces on the flat faces (both sides), in blade (y, z) coordinates
    def _face_x(self, y, s, out):
        h = self.at(y, "h")
        return s * (h + out)

    def inlay(self, strokes, width=0.03, raise_=0.012, sink=0.012, glow=True, rgb=None, sides=(1, -1)):
        """Strokes [[(y, z), ...], ...] as thin raised bars on both flat faces."""
        verts, faces = [], []
        for s in sides:
            for st in strokes:
                for (ya, za), (yb, zb) in zip(st, st[1:]):
                    d = Vector((0, yb - ya, zb - za))
                    if d.length < 1e-6:
                        continue
                    t = d.normalized() * (width / 2)
                    nrm = Vector((0, -t.z, t.y))
                    a = Vector((0, ya, za)) - t
                    b = Vector((0, yb, zb)) + t
                    quad = [a + nrm, b + nrm, b - nrm, a - nrm]
                    base = len(verts)
                    for out in (-sink, raise_):
                        for q in quad:
                            verts.append((self._face_x(q.y, s, out), q.y, q.z))
                    faces += [(base, base + 1, base + 2, base + 3), (base + 4, base + 7, base + 6, base + 5)]
                    for i in range(4):
                        j = (i + 1) % 4
                        faces.append((base + i, base + 4 + i, base + 4 + j, base + j))
        if not verts:
            return None
        o = H.flat(self.sw.nm("Inlay"), verts, faces, self.sw.gm if glow else self.sw.mat(rgb, roughness=0.3))
        self.attached.append(o)
        return self.sw.addg(o) if glow else self.sw.add(o)

    def slab(self, polys, raise_=0.014, sink=0.012, glow=True, rgb=None, sides=(1, -1)):
        """Filled polygons [(y, z), ...] as raised plates on both flat faces."""
        objs = []
        for poly in polys:
            for s in sides:
                n = len(poly)
                verts = [(self._face_x(y, s, out), y, z) for out in (-sink, raise_) for y, z in poly]
                faces = [tuple(range(n)), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
                objs.append(H.flat(self.sw.nm("Slab"), verts, faces, self.sw.gm if glow else self.sw.mat(rgb, roughness=0.3)))
        if not objs:
            return None
        o = C.join(objs, objs[0].name) if len(objs) > 1 else objs[0]
        C.recalc_normals(o)
        self.attached.append(o)
        return self.sw.addg(o) if glow else self.sw.add(o)

    def edge_glow(self, ya=None, yb=None, out=0.014, inn=0.05, pad=0.01):
        """Neon sleeve hugging the cutting edge between ya and yb."""
        ya = self.y0 + 0.02 if ya is None else ya
        yb = self.y1 if yb is None else yb
        ys = [y for y in self.ys if ya <= y <= yb]
        if not ys or ys[0] > ya + 1e-4:
            ys = [ya] + ys
        if ys[-1] < yb - 1e-4:
            ys.append(yb)
        verts, rings = [], []
        for y in ys:
            ze, h, b, e = self.at(y, "ze"), self.at(y, "h"), self.at(y, "b"), self.at(y, "e")
            dd = min(inn, b * 0.9)
            xs = e + (h - e) * min(1.0, dd / max(b, 1e-6))
            k = 1.0 if y < yb - 0.05 else 0.6
            ring = [(0, y, ze - out * k), (e + pad, y, ze), (xs + pad, y, ze + dd), (-xs - pad, y, ze + dd), (-e - pad, y, ze)]
            rings.append(list(range(len(verts), len(verts) + 5)))
            verts += ring
        o = H.flat(self.sw.nm("Edge"), verts, C.loft(rings), self.sw.gm)
        self.attached.append(o)
        return self.sw.addg(o)

    def attach(self, o):
        self.attached.append(o)
        return o

    def finish(self, rgb, roughness=0.35, record=True, **kw):
        sw = self.sw
        name = self.obj.name
        mat = H.decal_paint(name + "Mat", rgb, sw.save(name, self.decal), roughness=roughness, **kw)
        self.obj.data.materials.append(mat)
        sw.add(self.obj)
        y0, L = self.y0, self.L
        for o in [self.obj] + self.attached:
            for v in o.data.vertices:
                s = max(0.0, (v.co.y - y0) / L)
                v.co.z += self.bend_fn(s)
            o.data.update()
        if record:
            tipv = max(self.obj.data.vertices, key=lambda v: v.co.y).co
            sw.base = Vector((0, y0, 0))
            sw.tip = Vector((0, tipv.y, tipv.z))
        return self.obj


# ---------------------------------------------------------------- outlines
def katana_outline(y0, L, w, clip=0.5, wf=None, tip="clip", spine_pts=None, edge_pts=None, n=12, hook=0.0, center_z=0.0):
    """Edge/spine polylines for a katana-like blade of width w (wf(s) scales it).
    tip: "clip" (spine-side point, clipped edge like the tide blade), "center" (spear point),
    "hook" (point curls past the spine by `hook`), "tanto" (straight steep front).
    spine_pts / edge_pts: extra (s, dz) offsets merged in (teeth, flames, notches)."""
    wf = wf or (lambda s: 1.0)
    yc = y0 + L - clip
    base_s = [i / n for i in range(n + 1)]
    smax = (L - clip) / L
    edge, spine = [], []
    for s in base_s:
        s2 = s * smax
        y = y0 + L * s2
        edge.append((y, center_z - w * wf(s2) / 2))
        spine.append((y, center_z + w * wf(s2) / 2))

    def merge(poly, extra, sign):
        if not extra:
            return poly
        pts = dict((round(y, 5), z) for y, z in poly)
        for s, dz in extra:
            y = round(y0 + L * s, 5)
            z0 = interp(poly, y)
            pts[y] = z0 + sign * dz
        return sorted(pts.items())
    wt = w * wf(smax)
    zs_t, ze_t = center_z + wt / 2, center_z - wt / 2
    if tip == "clip":
        spine.append((y0 + L, zs_t))
        edge.append((y0 + L, zs_t - 0.004))
    elif tip == "center":
        m = center_z + wt * 0.12
        spine += [(yc + clip * 0.35, zs_t - wt * 0.08), (y0 + L, m + 0.003)]
        edge += [(yc + clip * 0.55, ze_t + wt * 0.25), (y0 + L, m - 0.003)]
    elif tip == "hook":
        spine += [(yc + clip * 0.45, zs_t + hook * 0.35), (y0 + L, zs_t + hook)]
        edge += [(yc + clip * 0.5, ze_t + wt * 0.45), (y0 + L, zs_t + hook - 0.004)]
    elif tip == "tanto":
        spine.append((y0 + L, zs_t))
        edge += [(yc + clip * 0.15, ze_t + wt * 0.08), (y0 + L, zs_t - 0.004)]
    spine = merge(spine, spine_pts, 1)
    edge = merge(edge, edge_pts, -1)
    return edge, spine


def teeth(s0, s1, n, depth, lean=0.6, jitter=None, rnd=None):
    """Sawtooth offsets [(s, dz)] for katana_outline: n teeth between s0 and s1, each
    rising over `lean` of its period (back-swept when lean > 0.5)."""
    out = []
    per = (s1 - s0) / n
    for i in range(n):
        a = s0 + i * per
        d = depth * (1 + (rnd.uniform(-jitter, jitter) if jitter and rnd else 0))
        out += [(a + 0.001, 0.0), (a + per * lean, d), (a + per * lean + 0.0025, d * 0.15), (a + per - 0.001, 0.0)]
    return out


def waves(s0, s1, n, amp, k=10):
    """Smooth sinusoidal offsets (flame / kris blades)."""
    out = []
    for i in range(n * k + 1):
        s = s0 + (s1 - s0) * i / (n * k)
        out.append((s, amp * math.sin((s - s0) / (s1 - s0) * n * math.pi * 2)))
    return out


# ---------------------------------------------------------------- 2D helpers (blade coords)
def star_poly(cy, cz, r_out, r_in, points=4, rot=0.0, squash=1.0):
    out = []
    for k in range(points * 2):
        a = rot + k * math.pi / points
        r = r_out if k % 2 == 0 else r_in
        out.append((cy + math.sin(a) * r, cz + math.cos(a) * r * squash))
    return out


def circle_poly(cy, cz, r, n=12, squash=1.0):
    return [(cy + math.sin(2 * math.pi * k / n) * r, cz + math.cos(2 * math.pi * k / n) * r * squash) for k in range(n)]


def diamond_poly(cy, cz, ry, rz):
    return [(cy + ry, cz), (cy, cz + rz), (cy - ry, cz), (cy, cz - rz)]


def flame_poly(cy, cz, h, w, lean=0.0, n=10):
    """Teardrop flame pointing +Y (blade coords), centred on (cy, cz)."""
    right, left = [], []
    for i in range(n + 1):
        t = i / n
        y = cy - h / 2 + h * t
        half = w / 2 * math.sin(math.pi * t ** 0.6)
        off = lean * t * t
        right.append((y, cz + half + off))
        if 0 < i < n:
            left.append((y, cz - half + off))
    return right + list(reversed(left))


def rune_strokes(cy, cz, size, rnd, aspect=0.75):
    """A random angular glyph in blade coords (y up, z across)."""
    raw = P.rune(0, 0, 1.0, rnd)
    return [[(cy - b * size, cz + a * size * aspect) for a, b in st] for st in raw]


def zigzag(ya, yb, zc, amp, n, rnd=None, jitter=0.0):
    pts = []
    for i in range(n + 1):
        t = i / n
        a = amp * (1 if i % 2 else -1) if 0 < i < n else 0.0
        if rnd and jitter:
            a *= 1 + rnd.uniform(-jitter, jitter)
        pts.append((ya + (yb - ya) * t, zc + a))
    return pts


def crack(rnd, ya, yb, zfn, amp, n=10, branches=3, blen=0.25):
    """Main jagged crack from ya to yb along z = zfn(y) plus short branches."""
    main = []
    for i in range(n + 1):
        y = ya + (yb - ya) * i / n
        main.append((y, zfn(y) + (rnd.uniform(-amp, amp) if 0 < i < n else 0)))
    out = [main]
    for _ in range(branches):
        i = rnd.randint(1, n - 1)
        y, z = main[i]
        side = rnd.choice((-1, 1))
        b = [(y, z)]
        for k in range(2):
            y += rnd.uniform(0.3, 0.6) * blen
            z += side * rnd.uniform(0.4, 0.8) * amp * 1.5
            b.append((y, z))
        out.append(b)
    return out
