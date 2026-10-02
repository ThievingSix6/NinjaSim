"""Merge the per-pack FBX files into one, so Studio needs a single Import 3D.
Checks every mesh against its manifest afterwards (same size and centre in Roblox space).

Run: python3 tools/blender/combine.py <out.fbx> <pack.fbx> [<pack.fbx> ...] -- <manifest.lua> [...]
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
from mathutils import Matrix  # noqa: E402

import common as C  # noqa: E402

args = sys.argv[1:]
split = args.index("--")
out, packs, manifests = args[0], args[1:split], args[split + 1:]


def import_packs(paths):
    C.reset_scene()
    for path in paths:
        bpy.ops.import_scene.fbx(filepath=path)
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.context.view_layer.update()
    for o in objs:
        o.parent = None
    bpy.context.view_layer.update()
    for o in objs:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    return objs


objs = import_packs(packs)
# Textured packs (UI icon atlas, hero katanas and ninjas) carry image textures; point
# each at its PNG on disk (assets/icons or assets/textures, by file name) so the
# exporter can embed it, and Studio's importer uploads it.
ASSETS = os.path.join(os.path.dirname(__file__), "..", "..", "assets")
has_images = False
by_path = {}
for img in list(bpy.data.images):
    if img.source != "FILE":
        continue
    base = os.path.splitext(os.path.basename(img.filepath or img.name))[0]
    base = base.split(".")[0]
    found = None
    for sub in ("icons", "textures"):
        cand = os.path.abspath(os.path.join(ASSETS, sub, base + ".png"))
        if os.path.exists(cand):
            found = cand
    if not found:
        print("IMAGE WITHOUT PNG ON DISK", img.name, img.filepath)
        continue
    if found in by_path:
        # the same PNG imported by several packs: keep one copy in the FBX
        img.user_remap(by_path[found])
        bpy.data.images.remove(img)
        continue
    by_path[found] = img
    if img.packed_file:
        img.unpack(method="REMOVE")
    img.filepath = found
    img.reload()
    has_images = True
C.export_fbx(out, objs, embed=has_images)

# verify: re-import the merged file and compare with the manifests
expected = {}
pat = re.compile(r'\["([\w]+)"\] = \{ Center = Vector3\.new\(([^)]*)\), Size = Vector3\.new\(([^)]*)\)')
for path in manifests:
    for name, c, s in pat.findall(open(path).read()):
        expected[name] = ([float(v) for v in c.split(",")], [float(v) for v in s.split(",")])
got = {o.name: C.bounds_roblox(o) for o in import_packs([out])}
bad = []
for name, (c, s) in expected.items():
    if name not in got:
        bad.append(name + " missing")
        continue
    gc, gs = got[name]
    if max(abs(a - b) for a, b in zip(gc, c)) > 0.01 or max(abs(a - max(b, 0.01)) for a, b in zip(gs, s)) > 0.01:
        bad.append("%s centre %s size %s (expected %s %s)" % (name, [round(v, 3) for v in gc], [round(v, 3) for v in gs], c, s))
print("MERGED", len(got), "meshes;", len(expected), "in manifests;", len(bad), "mismatches")
if has_images:
    packed = [(im.name, im.packed_file.size if im.packed_file else 0) for im in bpy.data.images]
    print("EMBEDDED IMAGES", len(packed), packed, "UIIconAtlas present:", "UIIconAtlas" in got)
for line in bad[:20]:
    print("  " + line)
