"""Enemy hats (head 1.25 cube) and weapons (grip at the origin, pointing Blender +Y).

Hats:     EnemyHat_Kasa Straw Band, EnemyHat_Kabuto Metal Crest Lace, EnemyHorns Horn,
          EnemyHat_Crown Gold Gems, EnemyHat_Bandana Cloth, EnemyHat_Topknot Hair
Weapons:  EnemyKanabo Wood Grip Studs, EnemyYari Shaft Blade Tassel, EnemyStaff Wood Metal Orb,
          EnemyKunai Blade Grip
Claws:    EnemyClaw Blade Band, EnemyClawL Blade (worn on the arm, arm reference 0.9 x 2 x 0.9)"""
import math

from mathutils import Matrix

import common as C
import sculpt as S
from kit import M, group, mirrored, place
from shapes import ribbon, shell, swept, tube


def rotate(objs, angle, axis):
    for o in objs:
        o.data.transform(Matrix.Rotation(angle, 4, axis))
        o.data.update()


# ================================================================== hats
def kasa():
    prof = [(0.0, 1.36), (0.12, 1.34), (0.3, 1.24), (0.8, 0.95), (1.45, 0.55), (1.5, 0.5), (1.46, 0.47), (0.8, 0.86), (0.25, 1.18), (0.0, 1.24)]
    cone = C.lathe("kasa", prof, 64, M["straw"], axis="Z")
    cone = S.subdivide(cone, 1)
    # woven straw: fine concentric ridges crossed by radial ribs
    S.displace(cone, lambda co, n: 0.012 * math.sin(math.hypot(co.x, co.y) * 70) + 0.008 * math.sin(math.atan2(co.y, co.x) * 48))
    knob = S.ellipsoid("knob", (0.1, 0.1, 0.08), (0, 0, 1.38), M["straw"])
    group("EnemyHat_Kasa__Straw", [cone, knob], "straw", 5000)
    band = tube("band", [(0.52, 0.66, 0.68), (0.66, 0.62, 0.64)], M["trim"], n=40, power=2.2, thick=0.05)
    ties = []
    for side in (-1, 1):
        pts = [(side * 0.58, 0.04, 0.58), (side * 0.6, 0.1, 0.2), (side * 0.5, 0.26, -0.3), (side * 0.2, 0.44, -0.62)]
        ties.append(ribbon("tie", pts, [(side, 0.3, 0)] * 4, 0.07, 0.025, M["trim"]))
    group("EnemyHat_Kasa__Band", [band] + ties, "trim", 1500)


def kabuto():
    dome = shell("dome", 0.72, (1.0, 1.04, 0.84), (0, -0.03, 0.2), lambda p: p.z > 0.18, M["metal"], thick=0.06, segs=48, rings=28, power=2.2)
    ribs = []
    for k in range(13):
        a = math.radians(-60 + k * 300 / 12)
        pts = [(math.cos(a) * 0.735 * math.cos(t), math.sin(a) * 0.765 * math.cos(t) - 0.03, 0.2 + 0.61 * math.sin(t)) for t in [i * (math.pi / 2) / 8 for i in range(9)]]
        ribs.append(swept("rib", pts, [0.022] * 8 + [0.01], M["metal"], n=6))
    tehen = C.cylinder("tehen", 0.1, 0.06, (0, -0.03, 0.8), M["metal"], 16, radius_top=0.07)
    visor = tube("visor", [(0.24, 0.76, 0.8), (0.14, 0.94, 1.02)], M["metal"], n=28, power=2.2, thick=0.04, arc=(math.radians(35), math.radians(145)))
    plates, lace = [], []
    for i in range(4):  # shikoro: neck guard lames flaring over the shoulders
        top = 0.22 - i * 0.18
        r0 = 0.78 + i * 0.09
        arc = (math.radians(150), math.radians(390))
        plates.append(tube("shikoro", [(top - 0.21, r0 + 0.1, r0 + 0.1), (top, r0, r0)], M["metal"], n=40, power=2.2, thick=0.045, arc=arc))
        lace.append(tube("lace", [(top - 0.225, r0 + 0.115, r0 + 0.115), (top - 0.195, r0 + 0.112, r0 + 0.112)], M["trim"], n=40, power=2.2, thick=0.025, arc=arc))
    for side in (-1, 1):  # fukigaeshi: the turned-back wings beside the face
        f = tube("fuki", [(-0.02, 0.2, 0.2), (0.26, 0.2, 0.2)], M["metal"], n=10, power=2.0, thick=0.04, arc=(math.radians(-60), math.radians(60)))
        place(f, (side * 0.7, 0.3, 0.02), (0, 0, math.radians(40 if side > 0 else 140)))
        plates.append(f)
    group("EnemyHat_Kabuto__Metal", [dome, tehen, visor] + ribs + plates, "metal", 6000)
    group("EnemyHat_Kabuto__Lace", lace, "trim", 1500)
    crest = []
    for side in (-1, 1):  # kuwagata: sweeping horns from the brow
        pts = [(side * (0.08 + 0.55 * t ** 1.4), 0.86 + 0.1 * t, 0.36 + 1.1 * t - 0.1 * t * t) for t in [i / 11 for i in range(12)]]
        crest.append(ribbon("kuwagata", pts, [(0, 1, 0)] * 12, [0.2 - 0.15 * (i / 11) for i in range(12)], 0.05, M["gold"]))
    disc = C.cylinder("disc", 0.17, 0.06, (0, 0, 0), M["gold"], 32)
    place(disc, (0, 0.9, 0.42), (-math.pi / 2, 0, 0))
    boss = S.ellipsoid("boss", (0.09, 0.05, 0.09), (0, 0.97, 0.42), M["gold"])
    group("EnemyHat_Kabuto__Crest", crest + [disc, boss], "gold", 2500)


def horns():
    parts = []
    for side in (-1, 1):
        verts = [(side * (0.3 + 0.28 * t + 0.16 * t * t), 0.12 - 0.36 * t * t, 0.45 + 0.8 * t - 0.14 * t * t) for t in [i / 7 for i in range(8)]]
        radii = [0.16 * (1 - i / 7) ** 0.8 + 0.012 for i in range(8)]
        h = S.skin("horn", verts, [(i, i + 1) for i in range(7)], radii, M["bone"], subdiv=2)
        S.displace(h, lambda co, n: 0.014 * math.sin(co.z * 36))
        parts.append(h)
    group("EnemyHorns__Horn", parts, "bone", 3000)


def crown():
    band = tube("band", [(0.44, 0.64, 0.66), (0.62, 0.66, 0.68), (0.66, 0.68, 0.7)], M["gold"], n=64, power=2.2, thick=0.06)
    spikes, gems = [], []
    for k in range(10):
        a = math.tau * k / 10 + math.pi / 2
        tall = k % 2 == 0
        h = 0.62 if tall else 0.36
        sp = S.skin("spike", [(0, 0, 0), (0, 0, h * 0.6), (0, 0, h)], [(0, 1), (1, 2)], [(0.13, 0.05), (0.08, 0.035), (0.01, 0.01)], M["gold"], subdiv=1)
        place(sp, (math.cos(a) * 0.68, math.sin(a) * 0.7, 0.62), (0, 0, a - math.pi / 2))
        spikes.append(sp)
        if tall:
            gems.append(S.ellipsoid("tip", (0.06, 0.06, 0.06), (math.cos(a) * 0.68, math.sin(a) * 0.7, 0.62 + h + 0.04), M["glow"]))
        gems.append(S.ellipsoid("gem", (0.07, 0.035, 0.09), (0, 0, 0), M["glow"], power=2.4))
        place(gems[-1], (math.cos(a) * 0.73, math.sin(a) * 0.75, 0.54), (0, 0, a - math.pi / 2))
    group("EnemyHat_Crown__Gold", [band] + spikes, "gold", 4000)
    group("EnemyHat_Crown__Gems", gems, "glow", 1500)


def bandana():
    band = tube("band", [(0.18, 0.64, 0.7), (0.37, 0.62, 0.68)], M["trim"], n=56, power=2.4, thick=0.05, center=(0, -0.04, 0))
    knot = S.ellipsoid("knot", (0.14, 0.1, 0.12), (0, -0.78, 0.28), M["trim"])
    tails = []
    for side in (-1, 1):
        pts, normals, widths = [], [], []
        for i in range(10):
            t = i / 9
            pts.append((side * (0.06 + 0.26 * t), -0.8 - 0.7 * t, 0.26 - 0.5 * t + 0.07 * math.sin(t * 7 + side)))
            normals.append((side * 0.7 * math.cos(t * 5), 0.0, 1.0))
            widths.append(0.17 - 0.05 * t)
        tails.append(ribbon("tail", pts, normals, widths, 0.03, M["trim"]))
    group("EnemyHat_Bandana__Cloth", [band, knot] + tails, "trim", 2000)


def topknot():
    bun = S.ellipsoid("bun", (0.16, 0.26, 0.14), (0, -0.08, 0.7), M["dark"])
    tail = S.skin("tail", [(0, 0.12, 0.72), (0, 0.32, 0.78), (0, 0.44, 0.72)], [(0, 1), (1, 2)], [0.08, 0.06, 0.02], M["dark"], subdiv=2)
    hair = S.fuse([bun, tail], "knot", M["dark"], voxel=0.018, smooth=3)
    S.displace(hair, lambda co, n: 0.01 * math.sin(co.x * 90))
    tie = tube("tie", [(0.62, 0.1, 0.1), (0.68, 0.1, 0.1)], M["dark"], n=16, power=2.0, thick=0.03, center=(0, -0.16, 0.08))
    group("EnemyHat_Topknot__Hair", [hair, tie], "dark", 1500)


# ================================================================== weapons (built along +Z, turned to +Y)
def kanabo():
    body = C.lathe("club", [(0.0, -0.5), (0.13, -0.5), (0.12, 0.6), (0.19, 0.75), (0.25, 1.3), (0.31, 2.7), (0.29, 3.05), (0.19, 3.2), (0.0, 3.25)], 8, M["dark"], axis="Z")
    pommel = tube("pommel", [(-0.56, 0.17, 0.17), (-0.46, 0.17, 0.17)], M["metal"], n=16, power=2.0, thick=0.04)
    grip = S.spiral_wrap("grip", -0.42, 0.56, 0.135, 7, 0.1, 0.03, M["trim"], steps=120)
    studs = []
    for i in range(7):
        z = 1.2 + i * 0.26
        r = 0.25 + (0.31 - 0.25) * min(1.0, (z - 1.3) / 1.4)
        for k in range(8):
            a = 2 * math.pi * (k + (0.5 if i % 2 else 0)) / 8
            s = C.cylinder("stud", 0.06, 0.13, (0, 0, 0), M["metal"], 6, radius_top=0.0)
            place(s, (math.cos(a) * r * 0.97, math.sin(a) * r * 0.97, z), (0, math.pi / 2, a))
            studs.append(s)
    for o in [body, grip, pommel] + studs:
        rotate([o], -math.pi / 2, "X")
    group("EnemyKanabo__Wood", [body], "dark")
    group("EnemyKanabo__Grip", [grip], "trim", 1200)
    group("EnemyKanabo__Studs", studs + [pommel], "metal", 2500)


def yari():
    shaft = C.cylinder("shaft", 0.075, 5.9, (0, 0, -1.5), M["wood"], 12)
    collar = C.cylinder("collar", 0.11, 0.25, (0, 0, 4.3), M["metal"], 12)
    butt = C.cylinder("butt", 0.09, 0.3, (0, 0, -1.6), M["metal"], 12, radius_top=0.08)
    outline = [(0.0, 0.0), (0.1, 0.12), (0.16, 0.45), (0.12, 0.8), (0.0, 1.25), (-0.12, 0.8), (-0.16, 0.45), (-0.1, 0.12)]
    blade = C.extrude_outline("blade", outline, 0.06, M["metal"], axis="Y", bevel=0.02)
    place(blade, (0, 0, 4.52))
    tassel = [C.blob("tassel", 0.16, (0, 0, 4.12), M["trim"], subdiv=2, noise=0.1, seed=5, squash=1.4)]
    for k in range(8):
        a = 2 * math.pi * k / 8
        tassel.append(swept("strand", [(math.cos(a) * 0.08, math.sin(a) * 0.08, 4.1), (math.cos(a) * 0.18, math.sin(a) * 0.18, 3.8), (math.cos(a) * 0.2, math.sin(a) * 0.2, 3.45)], [0.04, 0.035, 0.015], M["trim"], n=6))
    objs = [shaft, collar, blade, butt] + tassel
    rotate(objs, -math.pi / 2, "X")
    group("EnemyYari__Shaft", [shaft], "wood")
    group("EnemyYari__Blade", [collar, blade, butt], "metal")
    group("EnemyYari__Tassel", tassel, "trim", 1500)


def staff():
    shaft = C.cylinder("shaft", 0.085, 5.8, (0, 0, -2.9), M["wood"], 12)
    loop = tube("loop", [(-0.04, 0.42, 0.42), (0.04, 0.42, 0.42)], M["metal"], n=32, power=2.0, thick=0.06)
    rotate([loop], math.pi / 2, "X")
    loop.data.transform(Matrix.Translation((0, 0, 3.3)))
    rings = []
    for a in (-50, -20, 20, 50):
        rr = tube("ring", [(-0.02, 0.12, 0.12), (0.02, 0.12, 0.12)], M["metal"], n=16, power=2.0, thick=0.03)
        rotate([rr], math.pi / 2, "Y")
        rr.data.transform(Matrix.Translation((math.sin(math.radians(a)) * 0.46, 0, 3.3 + math.cos(math.radians(a)) * 0.46 - 0.12)))
        rings.append(rr)
    cap = C.cylinder("cap", 0.12, 0.2, (0, 0, 2.85), M["metal"], 12)
    orb = C.blob("orb", 0.24, (0, 0, 3.3), M["glow"], subdiv=3, noise=0.0)
    objs = [shaft, loop, cap, orb] + rings
    rotate(objs, -math.pi / 2, "X")
    group("EnemyStaff__Wood", [shaft], "wood")
    group("EnemyStaff__Metal", [loop, cap] + rings, "metal")
    group("EnemyStaff__Orb", [orb], "glow")


def kunai():
    outline = [(0.0, 1.35), (0.13, 0.55), (0.11, 0.3), (0.05, 0.22), (-0.05, 0.22), (-0.11, 0.3), (-0.13, 0.55)]
    blade = C.extrude_outline("blade", outline, 0.05, M["metal"], axis="Y", bevel=0.015)
    ridge = C.extrude_outline("ridge", [(0.0, 1.25), (0.02, 0.4), (-0.02, 0.4)], 0.07, M["metal"], axis="Y")
    ring = tube("ring", [(-0.025, 0.11, 0.11), (0.025, 0.11, 0.11)], M["metal"], n=20, power=2.0, thick=0.035)
    rotate([ring], math.pi / 2, "Y")
    ring.data.transform(Matrix.Translation((0, 0, -0.5)))
    grip = S.spiral_wrap("grip", -0.36, 0.2, 0.05, 6, 0.08, 0.025, M["trim"], steps=80)
    core = C.cylinder("core", 0.045, 0.6, (0, 0, -0.38), M["metal"], 10)
    objs = [blade, ridge, ring, grip, core]
    rotate(objs, -math.pi / 2, "X")
    group("EnemyKunai__Blade", [blade, ridge, ring, core], "metal")
    group("EnemyKunai__Grip", [grip], "trim", 800)


def claws():
    """Tekagi: a band over the knuckles with three hooked blades (arm reference, fist at z -0.84)."""
    band = tube("band", [(-0.9, 0.34, 0.34), (-0.76, 0.35, 0.35)], M["dark"], n=32, power=2.6, thick=0.05)
    blades = []
    for x in (-0.16, 0.0, 0.16):
        pts = [(x, 0.3 + 0.55 * t - 0.05 * t * t, -0.82 - 0.35 * t * t) for t in [i / 8 for i in range(9)]]
        radii = [(0.05 * (1 - i / 8) + 0.004, 0.02) for i in range(9)]
        blades.append(S.skin("claw", pts, [(i, i + 1) for i in range(8)], radii, M["metal"], subdiv=1))
    mirrored(group("EnemyClaw__Blade", blades, "metal", 1500), "EnemyClawL__Blade")
    group("EnemyClaw__Band", [band], "dark", 400)


def build():
    kasa()
    kabuto()
    horns()
    crown()
    bandana()
    topknot()
    kanabo()
    yari()
    staff()
    kunai()
    claws()
