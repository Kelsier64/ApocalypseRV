"""Render a raw GLB and optional candidates with one shared camera; never accepts an asset.

Output: <output>/<name>/{textured,clay}/<view>.png plus review.json (state UNKNOWN until
the agent has looked at every image and filled in checks/defects)."""
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

VIEWS = ("front", "side", "back", "oblique", "top", "underside")


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
    candidates = [Path(path).resolve() for path in args.candidate or []]
    original = decode(source)
    rotation = rigid_pose(Path(args.pose).resolve()) if args.pose else None
    exe = shutil.which(args.godot)
    require(exe is not None, "Godot executable unavailable")
    # Candidates are framed by the source bounds, so they must share its coordinate frame.
    files = [("source", source, original)]
    for index, path in enumerate(candidates, 1):
        files.append(("candidate" if len(candidates) == 1 else f"candidate_{index}", path, decode(path)))
    output.mkdir(parents=True, exist_ok=False)
    manifest = {"output": output.as_posix(), "rotation_rows": rotation,
                "models": [{"name": name, "path": path.as_posix(), "sha256": decoded[2]["sha256"]} for name, path, decoded in files]}
    save(output / "manifest.json", manifest)
    result = {"state": "UNKNOWN", "scope": "visual review", "source": original[2],
              "candidates": {name: decoded[2] for name, _, decoded in files[1:]},
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
    parser.add_argument("--candidate", action="append", help="repeatable; rendered with the source framing")
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
