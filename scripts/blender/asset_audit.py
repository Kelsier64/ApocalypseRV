"""Shared numeric audit for Blender-authored and generated assets.

Checks what renders hide: floating or disconnected parts, ground contact,
dimensions against the design size, triangle budget, open or non-manifold
geometry, degenerate faces, missing UVs, skin weights and (optionally)
self-intersection. It complements visual review; it does not replace it.

Headless (Blender is Z-up; GLBs are converted on import):
    blender --background --factory-startup --python scripts/blender/asset_audit.py -- \
        --glb assets/models/foo/foo.glb --size 0.6 0.6 0.9 --budget 8000 --output .godot/art-work/foo/audit.json
    blender --background art_source/foo/foo.blend --python scripts/blender/asset_audit.py -- --objects Body,Lid --strict

From the Blender MCP (execute_blender_code):
    import sys; sys.path.append(r"<repo>/scripts/blender"); import asset_audit
    report = asset_audit.audit(asset_audit.meshes(["Body"]), size=(0.6, 0.6, 0.9))

Asset-specific checks (animation clips, tooth occlusion, finger flexion) stay in
the asset's own script and call audit() for the shared part.
"""
import argparse
import json
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

GLTF_MAX_INFLUENCES = 4


def meshes(names=None):
    """Mesh objects by name, or every mesh in the current scene."""
    if names:
        missing = [n for n in names if n not in bpy.data.objects]
        if missing:
            raise SystemExit(f"Unknown objects: {missing}")
        return [bpy.data.objects[n] for n in names if bpy.data.objects[n].type == "MESH"]
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def _evaluated_bmesh(obj):
    """World-space, modifier-evaluated bmesh of obj (armature pose included)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.transform(obj.matrix_world)
    evaluated.to_mesh_clear()
    return bm


def _islands(bm):
    """Connected face groups as (face count, min corner, max corner)."""
    bm.faces.ensure_lookup_table()
    seen = set()
    result = []
    for face in bm.faces:
        if face.index in seen:
            continue
        stack = [face]
        seen.add(face.index)
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        count = 0
        while stack:
            current = stack.pop()
            count += 1
            for vert in current.verts:
                lo = Vector(map(min, lo, vert.co))
                hi = Vector(map(max, hi, vert.co))
            for edge in current.edges:
                for other in edge.link_faces:
                    if other.index not in seen:
                        seen.add(other.index)
                        stack.append(other)
        result.append((count, lo, hi))
    return result


def _touch(a, b, tolerance):
    return all(a[1][i] - tolerance <= b[2][i] and b[1][i] - tolerance <= a[2][i] for i in range(3))


def _skin(obj):
    """Unweighted vertices, weight sums off 1 and vertices over the glTF influence limit."""
    if not any(m.type == "ARMATURE" for m in obj.modifiers):
        return None
    deform = {g.index for g in obj.vertex_groups}
    unweighted = off_sum = over_limit = 0
    for vertex in obj.data.vertices:
        weights = [g.weight for g in vertex.groups if g.group in deform and g.weight > 1e-4]
        if not weights:
            unweighted += 1
            continue
        if abs(sum(weights) - 1.0) > 0.01:
            off_sum += 1
        if len(weights) > GLTF_MAX_INFLUENCES:
            over_limit += 1
    return {"unweighted_vertices": unweighted, "weight_sum_off_by_1pct": off_sum,
            f"vertices_over_{GLTF_MAX_INFLUENCES}_influences": over_limit}


def _self_intersections(bm):
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    tree = BVHTree.FromBMesh(bm, epsilon=0.0)
    pairs = 0
    for a, b in tree.overlap(tree):
        if a < b and not set(v.index for v in bm.faces[a].verts) & set(v.index for v in bm.faces[b].verts):
            pairs += 1
    return pairs


def audit(objects, size=None, size_tolerance=0.02, budget=None, ground=0.0,
          ground_tolerance=0.01, contact_tolerance=0.005, self_intersection=False):
    """Audit mesh objects as one asset. Returns a report dict with an `issues` list."""
    report = {"objects": [], "issues": []}
    islands = []
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    triangles = 0
    for obj in objects:
        bm = _evaluated_bmesh(obj)
        tri = sum(len(f.verts) - 2 for f in bm.faces)
        triangles += tri
        nonmanifold = sum(1 for e in bm.edges if len(e.link_faces) > 2)
        boundary = sum(1 for e in bm.edges if len(e.link_faces) == 1)
        degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-10)
        loose_verts = sum(1 for v in bm.verts if not v.link_edges)
        loose_edges = sum(1 for e in bm.edges if not e.link_faces)
        object_islands = _islands(bm)
        for island in object_islands:
            islands.append((obj.name,) + island)
            lo = Vector(map(min, lo, island[1]))
            hi = Vector(map(max, hi, island[2]))
        row = {"name": obj.name, "triangles": tri, "islands": len(object_islands),
               "nonmanifold_edges": nonmanifold, "boundary_edges": boundary,
               "degenerate_faces": degenerate, "loose_vertices": loose_verts, "loose_edges": loose_edges,
               "uv_layers": len(obj.data.uv_layers), "materials": len(obj.data.materials)}
        skin = _skin(obj)
        if skin is not None:
            row["skin"] = skin
            for key, value in skin.items():
                if value:
                    report["issues"].append(f"{obj.name}: {value} {key.replace('_', ' ')}")
        if self_intersection:
            row["self_intersecting_face_pairs"] = _self_intersections(bm)
            if row["self_intersecting_face_pairs"]:
                report["issues"].append(f"{obj.name}: {row['self_intersecting_face_pairs']} self-intersecting face pairs")
        for key in ("nonmanifold_edges", "degenerate_faces", "loose_vertices", "loose_edges"):
            if row[key]:
                report["issues"].append(f"{obj.name}: {row[key]} {key.replace('_', ' ')}")
        if not row["uv_layers"]:
            report["issues"].append(f"{obj.name}: no UV layer")
        report["objects"].append(row)
        bm.free()
    if not islands:
        report["issues"].append("No mesh geometry")
        return report
    # A part is supported when it touches the ground or a chain of parts that does.
    supported = [island[2].z <= ground + ground_tolerance for island in islands]
    pending = [i for i, ok in enumerate(supported) if ok]
    while pending:
        current = islands[pending.pop()]
        for j, other in enumerate(islands):
            if not supported[j] and _touch(current[1:], other[1:], contact_tolerance):
                supported[j] = True
                pending.append(j)
    floating = [{"object": isl[0], "faces": isl[1], "min": list(isl[2]), "max": list(isl[3])}
                for isl, ok in zip(islands, supported) if not ok]
    for part in floating:
        report["issues"].append(f"{part['object']}: {part['faces']}-face part at z {part['min'][2]:.3f} touches nothing")
    report.update({"triangles": triangles, "islands": len(islands), "floating_parts": floating,
                   "bounds_min": list(lo), "bounds_max": list(hi), "size": list(hi - lo),
                   "ground_offset": lo.z - ground})
    if abs(lo.z - ground) > ground_tolerance:
        report["issues"].append(f"Lowest point is {lo.z - ground:+.3f} m from the ground")
    if size:
        error = max(abs(a - b) for a, b in zip(hi - lo, size))
        report["size_error"] = error
        if error > size_tolerance:
            report["issues"].append(f"Size {tuple(round(v, 3) for v in hi - lo)} differs from {tuple(size)} by {error:.3f} m")
    if budget is not None and triangles > budget:
        report["issues"].append(f"{triangles} triangles exceed the budget of {budget}")
    return report


def main(argv):
    parser = argparse.ArgumentParser(prog="asset_audit")
    parser.add_argument("--glb", help="import this GLB into an empty scene first")
    parser.add_argument("--objects", help="comma-separated mesh object names; default every mesh")
    parser.add_argument("--size", type=float, nargs=3, help="design size X Y Z in metres (Blender axes)")
    parser.add_argument("--size-tolerance", type=float, default=0.02)
    parser.add_argument("--budget", type=int)
    parser.add_argument("--ground", type=float, default=0.0)
    parser.add_argument("--self-intersection", action="store_true")
    parser.add_argument("--output", help="write the JSON report here")
    parser.add_argument("--strict", action="store_true", help="exit 1 when any issue is found")
    args = parser.parse_args(argv)
    if args.glb:
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.ops.import_scene.gltf(filepath=str(Path(args.glb).resolve()))
    names = [n.strip() for n in args.objects.split(",")] if args.objects else None
    report = audit(meshes(names), size=args.size, size_tolerance=args.size_tolerance, budget=args.budget,
                   ground=args.ground, self_intersection=args.self_intersection)
    text = json.dumps(report, indent=2)
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(text + "\n", encoding="utf-8")
    print("AUDIT " + json.dumps({"issues": report["issues"], "triangles": report.get("triangles")}))
    if args.strict and report["issues"]:
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
