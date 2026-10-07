"""Render preserved gltfpack candidates with one baseline camera; does not accept them."""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILL = HERE.parents[1] / ".agents/skills/comfyui-image-to-3d/scripts"
sys.path.insert(0, str(SKILL))
from review import decode, images, VIEWS


def main():
    output = HERE / "review_reductions"
    output.mkdir(exist_ok=False)
    paths = {"source_49k": HERE / "fitted_49k/source.glb",
             "candidate_20k": HERE / "gltfpack_20k/candidate.glb",
             "candidate_15k": HERE / "gltfpack_10k/candidate.glb"}
    decoded = {name: decode(path) for name, path in paths.items()}
    texture_hashes = images(*decoded["source_49k"][:2])
    assert all(images(*item[:2]) == texture_hashes for item in decoded.values())
    manifest = {"output": output.as_posix(), "rotation_rows": None,
                "models": [{"name": name, "path": path.as_posix(),
                            "sha256": decoded[name][2]["sha256"]} for name, path in paths.items()]}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    with tempfile.TemporaryDirectory(prefix="generator-reduction-") as tmp:
        viewer = Path(tmp)
        shutil.copyfile(SKILL / "render_views.gd", viewer / "render_views.gd")
        (viewer / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Generator reduction review"\n[display]\nwindow/size/viewport_width=720\nwindow/size/viewport_height=720\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = subprocess.SW_HIDE
        with (output / "stdout.log").open("w") as stdout, (output / "stderr.log").open("w") as stderr:
            result = subprocess.run(["C:/Program Files/godot/godot.exe", "--path", str(viewer),
                                     "--rendering-method", "gl_compatibility", "--log-file", str(output / "godot.log"),
                                     "--script", "res://render_views.gd", "--", str(output / "manifest.json")],
                                    stdout=stdout, stderr=stderr, startupinfo=startup,
                                    creationflags=subprocess.CREATE_NO_WINDOW, timeout=180)
        assert result.returncode == 0
    logs = "\n".join((output / name).read_text(errors="replace") for name in ("stdout.log", "stderr.log", "godot.log"))
    assert "ERROR:" not in logs
    for name, path in paths.items():
        stats = json.loads((output / name / "godot_review.json").read_text())
        assert stats["sha256"] == decoded[name][2]["sha256"]
        assert stats["triangles"] == decoded[name][2]["triangles"]
        assert decode(path)[2]["sha256"] == stats["sha256"]
        assert all((output / name / mode / (view + ".png")).is_file()
                   for mode in ("textured", "clay") for view in VIEWS)
    review = {"state": "RENDERED_NOT_ACCEPTED", "shared_baseline_camera": True,
              "models": {name: item[2] for name, item in decoded.items()},
              "embedded_image_sha256": texture_hashes,
              "integrity_scope": "container, finite attributes, indices, counts and unchanged image bytes; vertices/UVs updated by gltfpack",
              "views_inspected": [], "selection": None}
    (output / "review.json").write_text(json.dumps(review, indent=2) + "\n")
    print(json.dumps(review))


if __name__ == "__main__":
    main()
