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
    raw = decode(HERE / "run_01/raw.glb")
    high = decode(HERE / "fitted_49k/source.glb")
    candidate = decode(HERE / "gltfpack_20k/candidate.glb")
    doc, binary, stats = decode(ASSETS / "bunker_diesel_generator.glb")
    meta = load(HERE / "refinement.json")
    assert raw[2]["sha256"] == "34a0f1f5cfa865acfa07970ceda8199ff77e2264662350cb108fd04887007b8c"
    assert high[2]["sha256"] == "2466a3e847a9429229ff63c0970bf01d410afe0e74d94fcb7abebaa56912c91d"
    assert candidate[2]["sha256"] == meta["source_sha256"]
    assert stats["sha256"] == meta["final_sha256"]
    assert raw[2]["triangles"] == high[2]["triangles"] == 49923
    assert candidate[2]["triangles"] == stats["triangles"] == 19968
    assert images(doc, binary) == images(*raw[:2]) == images(*high[:2]) == images(*candidate[:2])
    assert not doc.get("extensionsRequired") and not doc.get("animations") and not doc.get("skins")
    primitive = doc["meshes"][0]["primitives"][0]
    cp = candidate[0]["meshes"][0]["primitives"][0]
    assert set(primitive["attributes"]) == {"POSITION", "NORMAL", "TEXCOORD_0", "TANGENT"}
    # Metric refit must not alter the reduced candidate's topology or UVs.
    assert tuples(doc, binary, primitive["attributes"]["TEXCOORD_0"]) == tuples(*candidate[:2], cp["attributes"]["TEXCOORD_0"])
    def index_bytes(d, b, p):
        acc = d["accessors"][p["indices"]]
        view = d["bufferViews"][acc["bufferView"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        return acc["componentType"], b[start:start + acc["count"] * {5123: 2, 5125: 4}[acc["componentType"]]]
    assert index_bytes(doc, binary, primitive) == index_bytes(*candidate[:2], cp)
    normals = [struct.unpack("<fff", x) for x in tuples(doc, binary, primitive["attributes"]["NORMAL"])]
    tangents = [struct.unpack("<ffff", x) for x in tuples(doc, binary, primitive["attributes"]["TANGENT"])]
    assert all(abs(sum(x*x for x in n) - 1) < 1e-5 for n in normals)
    assert all(abs(sum(x*x for x in t[:3]) - 1) < 1e-5 and t[3] in (-1, 1) for t in tangents)
    assert all(abs(sum(n[i]*t[i] for i in range(3))) < 1e-5 for n, t in zip(normals, tangents))
    for semantic in primitive["attributes"]:
        tuples(doc, binary, primitive["attributes"][semantic])  # all finite
    assert doc["materials"] == candidate[0]["materials"]
    editable = load(HERE / "editable/bunker_diesel_generator.gltf")
    assert (HERE / "editable" / editable["buffers"][0]["uri"]).read_bytes() == binary
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
    review = load(HERE / "review_reduced_final/review.json")
    assert review["source"]["sha256"] == stats["sha256"] and review["state"] == "ACCEPTED_WITH_LIMITATIONS"
    assert load(HERE / "in_context/validation.json")["state"] == "PASS"
    # Check the saved historical evidence, without depending on a local cache or current Git HEAD.
    # Fresh behavior tests are run separately through scripts/test.ps1.
    runner = load(validation / "runner-reduced-results.json")
    assert all(item["status"] == "PASS" for item in runner["results"])
    capture = validation / "capture-reduced.log"
    assert "ERROR:" not in capture.read_text(encoding="utf-8")
    checks = {"state": "PASS", "raw_sha256": raw[2]["sha256"], "final_sha256": stats["sha256"],
              "input_triangles": raw[2]["triangles"], "final_triangles": stats["triangles"],
              "reduction_percent": (1 - stats["triangles"] / raw[2]["triangles"]) * 100,
              "original_scene_sections_preserved": True, "embedded_texture_bytes_preserved": True,
              "raw_indices_uv_preserved": False, "reduced_candidate_indices_uv_preserved_during_refit": True,
              "finite_attributes_unit_normals_orthogonal_tangents": True,
              "editable_external_files_verified": True, "fps_measured": False}
    (validation / "delivery-reduced-checks.json").write_text(json.dumps(checks, indent=2) + "\n")
    print(json.dumps(checks))


if __name__ == "__main__":
    main()
