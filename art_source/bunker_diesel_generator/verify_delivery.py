"""Validate the selected reduced delivery; acceptance remains a recorded visual decision."""
import hashlib
import json
import re
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ASSETS = ROOT / "assets/models/bunker_diesel_generator"
sys.path.insert(0, str(ROOT / ".agents/skills/comfyui-image-to-3d/scripts"))
from review import decode, images, tuples


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    raw = decode(HERE / "raw.glb")
    doc, binary, stats = decode(ASSETS / "bunker_diesel_generator.glb")
    meta = load(HERE / "refinement.json")
    assert raw[2]["sha256"] == "34a0f1f5cfa865acfa07970ceda8199ff77e2264662350cb108fd04887007b8c"
    generation = load(HERE / "generation.json")
    assert hashlib.sha256((HERE / "prompt.json").read_bytes()).hexdigest() == generation["prompt_sha256"]
    assert hashlib.sha256((HERE / "reference.png").read_bytes()).hexdigest() == generation["reference_sha256"]
    assert hashlib.sha256((HERE / "conditioning.png").read_bytes()).hexdigest() == generation["conditioning_sha256"]
    assert meta["source_sha256"] == "2d0267dda6918fb41c47a18940267ca7f9767fbe55f0a03aba7df883dbe115f3"
    assert stats["sha256"] == meta["final_sha256"]
    assert raw[2]["triangles"] == 49923 and stats["triangles"] == 19968
    assert images(doc, binary) == images(*raw[:2])
    assert not doc.get("extensionsRequired") and not doc.get("animations") and not doc.get("skins")
    primitive = doc["meshes"][0]["primitives"][0]
    assert set(primitive["attributes"]) == {"POSITION", "NORMAL", "TEXCOORD_0", "TANGENT"}
    points = [struct.unpack("<fff", x) for x in tuples(doc, binary, primitive["attributes"]["POSITION"])]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    assert all(abs(high[i] - low[i] - (3.2, 1.7, 1.2)[i]) < 0.002 for i in range(3))
    assert all(abs(low[i] - (-1.6, 0, -0.6)[i]) < 0.002 for i in range(3))
    normals = [struct.unpack("<fff", x) for x in tuples(doc, binary, primitive["attributes"]["NORMAL"])]
    tangents = [struct.unpack("<ffff", x) for x in tuples(doc, binary, primitive["attributes"]["TANGENT"])]
    assert all(abs(sum(x*x for x in n) - 1) < 1e-5 for n in normals)
    assert all(abs(sum(x*x for x in t[:3]) - 1) < 1e-5 and t[3] in (-1, 1) for t in tangents)
    assert all(abs(sum(n[i]*t[i] for i in range(3))) < 1e-5 for n, t in zip(normals, tangents))
    for semantic in primitive["attributes"]:
        tuples(doc, binary, primitive["attributes"][semantic])  # all finite
    editable = load(HERE / "editable/bunker_diesel_generator.gltf")
    assert (HERE / "editable" / editable["buffers"][0]["uri"]).read_bytes() == binary
    for key in ("accessors", "bufferViews", "meshes", "nodes", "materials", "textures", "samplers"):
        assert editable.get(key) == doc.get(key), key
    for name, entry in zip(("basecolor", "orm", "normal"), editable["images"]):
        texture = HERE / "editable" / entry["uri"]
        assert hashlib.sha256(texture.read_bytes()).hexdigest() == meta["texture_sha256"][name]
        assert (ASSETS / texture.name).read_bytes() == texture.read_bytes()
    scene = "world/poi_kit/furniture/bunker/diesel_generator_graybox.tscn"
    validation = HERE / "validation"
    baseline = load(validation / "wrapper_baseline.json")
    original_bytes = (validation / "wrapper_original.tscn").read_bytes()
    assert hashlib.sha256(original_bytes).hexdigest() == baseline["sha256"]
    original = original_bytes.decode("utf-8")
    def sections(text):
        return {m.group(1): m.group(2).strip() for m in re.finditer(r"(?m)^(\[[^\n]+\])\n(.*?)(?=^\[|\Z)", text, re.S | re.M)}
    before, after = sections(original), sections((ROOT / scene).read_text())
    for header, body in before.items():
        assert header in after
        actual = after[header]
        if any('name="' + name + '"' in header for name in ("Blockout", "Cover", "Stencil")):
            actual = actual.replace("visible = false\n", "")
        assert actual == body, header
    review = load(validation / "review.json")
    assert review["source"]["sha256"] == stats["sha256"] and review["state"] == "ACCEPTED_WITH_LIMITATIONS"
    assert load(validation / "context.json")["state"] == "PASS"
    # Check the saved historical evidence, without depending on a local cache or current Git HEAD.
    # Fresh behavior tests are run separately through scripts/test.ps1.
    runner = load(validation / "runner-results.json")
    assert all(item["status"] == "PASS" for item in runner["results"])
    checks = {"state": "PASS", "raw_sha256": raw[2]["sha256"], "final_sha256": stats["sha256"],
              "input_triangles": raw[2]["triangles"], "final_triangles": stats["triangles"],
              "reduction_percent": (1 - stats["triangles"] / raw[2]["triangles"]) * 100,
              "original_scene_sections_preserved": True, "embedded_texture_bytes_preserved": True,
              "raw_indices_uv_preserved": False, "editable_vertex_index_material_data_matches_glb": True,
              "dimensions_bottom_center": True, "generation_hashes_preserved": True,
              "finite_attributes_unit_normals_orthogonal_tangents": True,
              "editable_external_files_verified": True, "fps_measured": False}
    (validation / "delivery-checks.json").write_text(json.dumps(checks, indent=2) + "\n")
    print(json.dumps(checks))


if __name__ == "__main__":
    main()
