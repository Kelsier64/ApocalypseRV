"""Validate preserved GLBs and render comparable views; never accept an asset automatically."""
import argparse
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

from generate import inspect_glb, read, save, sha

VIEWS = ("front", "side", "back", "oblique", "top")
SEMANTICS = {"POSITION": "VEC3", "NORMAL": "VEC3", "TEXCOORD_0": "VEC2", "TANGENT": "VEC4"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def decode(path):
    data = path.read_bytes()
    stats = inspect_glb(data)
    length = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + length])
    binary = data[28 + length:]
    require(len(doc["buffers"]) == 1 and not doc["buffers"][0].get("uri"), "Expected one embedded buffer")
    require(0 <= len(binary) - doc["buffers"][0]["byteLength"] <= 3, "Invalid BIN padding")
    stats.update(sha256=sha(data), bytes=len(data))
    return doc, binary, stats


def tuples(doc, binary, accessor_id):
    acc = doc["accessors"][accessor_id]
    view = doc["bufferViews"][acc["bufferView"]]
    require(acc["componentType"] == 5126 and not acc.get("sparse") and not acc.get("normalized"), "Expected float32 attributes")
    require(view.get("buffer", 0) == 0, "Attribute buffer must be embedded")
    components = {"VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    width = components * 4
    stride = view.get("byteStride", width)
    offset = acc.get("byteOffset", 0)
    require(acc["count"] > 0 and stride >= width and offset >= 0, "Invalid attribute count/stride/offset")
    end = offset + (acc["count"] - 1) * stride + width
    require(end <= view["byteLength"] and view.get("byteOffset", 0) + end <= len(binary), "Attribute exceeds buffer")
    start = view.get("byteOffset", 0) + offset
    result = [binary[start + i * stride:start + i * stride + width] for i in range(acc["count"])]
    require(all(math.isfinite(x) for item in result for x in struct.unpack("<" + "f" * components, item)), "Non-finite vertex attribute")
    return result


def images(doc, binary):
    result = []
    for image in doc["images"]:
        require(not image.get("uri"), "External image unsupported")
        view = doc["bufferViews"][image["bufferView"]]
        start, length = view.get("byteOffset", 0), view["byteLength"]
        require(view.get("buffer", 0) == 0 and start >= 0 and length > 0 and start + length <= len(binary), "Invalid image buffer")
        result.append(sha(binary[start:start + length]))
    return result


def verify_reduction(source, candidate, original, reduced):
    sd, sb, ss = original
    cd, cb, cs = reduced
    meta = read(candidate.parent / "simplification.json")
    mapping = read(candidate.parent / "vertex_mapping.json")
    require(meta["source_sha256"] == ss["sha256"] and meta["output_sha256"] == cs["sha256"], "Reduction hashes disagree with files")
    require(meta["input_triangles"] == ss["triangles"] and meta["actual_triangles"] == cs["triangles"], "Reduction triangle counts disagree")
    require(meta["package_version"] == "1.3.0", "Unexpected simplifier version")
    profile = meta["profile"]
    require(profile["method"] == "simplifyWithAttributes" and profile["flags"] == ["LockBorder"], "Unexpected reduction method/flags")
    require(profile["normal_weights"] == [1, 1, 1] and profile["uv_weights"] == [10, 10], "Unexpected attribute weights")
    require(profile["vertex_lock"] is None and not any(profile[k] for k in ("permissive", "update_vertices", "prune")), "Unexpected geometry edits")
    force = profile["force_target"]
    require(profile["error_limit_disabled"] == force and profile["relative_error_limit"] == (None if force else 0.002), "Unexpected error limit")
    error = meta["reported_relative_combined_error"]
    require(math.isfinite(error) and error >= 0 and (force or error <= 0.002 + 1e-6), "Reduction exceeded error cap")
    reached = cs["triangles"] <= meta["requested_triangles"]
    require(reached == meta["target_reached"] and (not force or reached), "Target status incorrect")
    for key in ("materials", "samplers", "textures", "nodes", "scenes", "scene"):
        require(sd.get(key) == cd.get(key), "Changed " + key)
    sp, cp = sd["meshes"][0]["primitives"][0], cd["meshes"][0]["primitives"][0]
    require(sp.get("material") == cp.get("material"), "Changed material assignment")
    require(set(sp["attributes"]) == set(SEMANTICS) == set(cp["attributes"]), "Unexpected vertex semantics")
    require(len(mapping) == cs["vertices"] and all(type(i) is int and 0 <= i < ss["vertices"] for i in mapping), "Invalid source vertex mapping")
    for semantic, wanted_type in SEMANTICS.items():
        require(sd["accessors"][sp["attributes"][semantic]]["type"] == wanted_type and cd["accessors"][cp["attributes"][semantic]]["type"] == wanted_type, "Wrong attribute type")
        before = tuples(sd, sb, sp["attributes"][semantic])
        after = tuples(cd, cb, cp["attributes"][semantic])
        require(after == [before[i] for i in mapping], "Modified source attribute: " + semantic)
    require(images(sd, sb) == images(cd, cb) == meta["image_sha256"], "Embedded textures changed")
    require(sha(source.read_bytes()) == ss["sha256"], "Source changed")
    return {"state": "PASS", "scope": "container/counts/vertex-tuples/materials/textures only", "target_reached": reached,
            "requested_triangles": meta["requested_triangles"], "actual_triangles": cs["triangles"],
            "force_target": force, "reported_relative_combined_error": error, "geometry_straightness_checked": False}


def rigid_pose(path):
    if path is None:
        return None
    rows = read(path)["rotation_rows"]
    require(len(rows) == 3 and all(len(row) == 3 for row in rows), "Pose must be 3x3")
    require(all(math.isfinite(x) for row in rows for x in row), "Pose is non-finite")
    for i in range(3):
        for j in range(3):
            require(abs(sum(rows[i][k] * rows[j][k] for k in range(3)) - (1 if i == j else 0)) < 1e-5, "Pose contains axis scaling/shear")
    a, b, c = rows
    det = a[0]*(b[1]*c[2]-b[2]*c[1])-a[1]*(b[0]*c[2]-b[2]*c[0])+a[2]*(b[0]*c[1]-b[1]*c[0])
    require(abs(det - 1) < 1e-5, "Pose contains reflection")
    return rows


def run(args):
    output = Path(args.output).resolve()
    require(not output.exists(), "Output already exists: refuse overwrite")
    source = Path(args.source).resolve()
    candidate = Path(args.candidate).resolve() if args.candidate else None
    original = decode(source)
    reduced = decode(candidate) if candidate else None
    integrity = verify_reduction(source, candidate, original, reduced) if candidate else None
    rotation = rigid_pose(Path(args.pose).resolve()) if args.pose else None
    exe = shutil.which(args.godot)
    require(exe is not None, "Godot executable unavailable")
    output.mkdir(parents=True, exist_ok=False)
    files = [("source", source, original)]
    if candidate:
        files.append(("candidate", candidate, reduced))
    manifest = {"output": output.as_posix(), "rotation_rows": rotation,
                "models": [{"name": name, "path": path.as_posix(), "sha256": decoded[2]["sha256"]} for name, path, decoded in files]}
    save(output / "manifest.json", manifest)
    result = {"state": "UNKNOWN", "scope": "candidate review", "source": original[2],
              "candidate": reduced[2] if reduced else None, "integrity": integrity,
              "pose": "source up" if rotation is None else "explicit rigid rotation; source-up review also required",
              "views_inspected": [], "checks": {}, "defects": [],
              "limitations": ["No visual, dimension, straightness, support-plane or interface acceptance has been performed."]}
    save(output / "review.json", result)
    # Isolated project avoids the game's autoloads and asset import changes.
    with tempfile.TemporaryDirectory(prefix="comfy-3d-viewer-") as temporary:
        viewer = Path(temporary)
        shutil.copyfile(Path(__file__).with_name("render_views.gd"), viewer / "render_views.gd")
        (viewer / "project.godot").write_text('config_version=5\n[application]\nconfig/name="3D candidate review"\n[display]\nwindow/size/viewport_width=720\nwindow/size/viewport_height=720\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
        command = [exe, "--path", str(viewer), "--rendering-method", "gl_compatibility", "--log-file", str(output / "godot.log"), "--script", "res://render_views.gd", "--", str(output / "manifest.json")]
        creationflags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        with (output / "stdout.log").open("w", encoding="utf-8") as stdout, (output / "stderr.log").open("w", encoding="utf-8") as stderr:
            startup = None
            if sys.platform == "win32":
                startup = subprocess.STARTUPINFO()
                startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                startup.wShowWindow = subprocess.SW_HIDE
            process = subprocess.run(command, stdout=stdout, stderr=stderr, creationflags=creationflags, startupinfo=startup, timeout=180)
        require(process.returncode == 0, "Godot rendering failed: inspect saved logs; review remains UNKNOWN")
    logs = "\n".join((output / name).read_text(encoding="utf-8", errors="replace") for name in ("godot.log", "stdout.log", "stderr.log"))
    require("SCRIPT ERROR:" not in logs and "ERROR:" not in logs, "Godot reported errors: review remains UNKNOWN")
    for name, path, decoded in files:
        stats = read(output / name / "godot_review.json")
        require(stats["sha256"] == decoded[2]["sha256"] and stats["triangles"] == decoded[2]["triangles"], "Rendered model/hash/count mismatch")
        require(sha(path.read_bytes()) == decoded[2]["sha256"], "Model changed during render")
        for mode in ("textured", "clay"):
            for view in VIEWS:
                require((output / name / mode / (view + ".png")).is_file(), "Missing review image")
    result["rendering"] = {"state": "PASS", "scope": "files rendered, not visually accepted", "views": list(VIEWS), "modes": ["textured", "clay"], "shared_baseline_camera": True}
    save(output / "review.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--candidate")
    parser.add_argument("--output", required=True)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--pose")
    try:
        print(json.dumps(run(parser.parse_args()), ensure_ascii=False))
    except Exception as exc:
        print(json.dumps({"state": "STOPPED", "reason": str(exc)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
