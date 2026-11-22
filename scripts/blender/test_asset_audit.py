"""Offline test for asset_audit.py. Run:
    blender --background --factory-startup --python scripts/blender/test_asset_audit.py
"""
import sys
from pathlib import Path

import bpy

sys.path.append(str(Path(__file__).resolve().parent))
import asset_audit  # noqa: E402

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)
        print("FAIL: " + message)


def reset():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def cube(name, location, size=1.0):
    bpy.ops.mesh.primitive_cube_add(size=size, location=location)
    obj = bpy.context.active_object
    obj.name = name
    return obj


reset()
base = cube("Base", (0, 0, 0.5))
lid = cube("Lid", (0, 0, 1.25), 0.5)
clean = asset_audit.audit([base, lid], size=(1, 1, 1.5), budget=100)
check(not clean["issues"], f"Stacked cubes on the ground pass: {clean['issues']}")
check(clean["triangles"] == 24 and clean["islands"] == 2, "Counts triangles and islands")

reset()
base = cube("Base", (0, 0, 0.5))
loose = cube("Loose", (3, 0, 2.0), 0.5)
report = asset_audit.audit([base, loose])
check(len(report["floating_parts"]) == 1 and report["floating_parts"][0]["object"] == "Loose", "Flags the floating part")

reset()
raised = cube("Raised", (0, 0, 0.7))
report = asset_audit.audit([raised], size=(1, 1, 1), budget=4)
messages = " ".join(report["issues"])
check("from the ground" in messages, "Flags a model that does not sit on the ground")
check("exceed the budget" in messages, "Flags a triangle budget overrun")
check("touches nothing" in messages, "A raised single part is also floating")

reset()
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
plane = bpy.context.active_object
report = asset_audit.audit([plane], size=(2, 2, 0))
check(report["objects"][0]["boundary_edges"] == 4, "Reports open boundary edges")
check(any("differs" in issue for issue in report["issues"]), "Flags a size mismatch")

reset()
a = cube("A", (0, 0, 0.5))
b = cube("B", (0.3, 0, 0.5))
bpy.ops.object.select_all(action="DESELECT")
a.select_set(True)
b.select_set(True)
bpy.context.view_layer.objects.active = a
bpy.ops.object.join()
report = asset_audit.audit([a], self_intersection=True)
check(report["objects"][0]["self_intersecting_face_pairs"] > 0, "Finds overlapping parts in one mesh")

if failures:
    print(f"FAILED {len(failures)}")
    sys.exit(1)
print("PASS: asset_audit")
