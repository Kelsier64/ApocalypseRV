"""Read-only GLB contract audit; emits JSON evidence without changing the asset."""
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / "assets/models/player_test_v020/player_export_test_v020.glb"
blob = path.read_bytes()
magic, version, length = struct.unpack_from("<III", blob)
assert magic == 0x46546C67 and version == 2 and length == len(blob)
json_length, json_type = struct.unpack_from("<II", blob, 12)
assert json_type == 0x4E4F534A
doc = json.loads(blob[20:20 + json_length])
offset = 20 + json_length
bin_length, bin_type = struct.unpack_from("<II", blob, offset)
assert bin_type == 0x004E4942
binary = blob[offset + 8:offset + 8 + bin_length]
nodes = doc["nodes"]
skins = doc["skins"]
joint_names = [nodes[i]["name"] for i in skins[0]["joints"]]
assert len(skins) == 1 and len(joint_names) == 41
assert not any(n.startswith(("CTRL", "POLE")) for n in joint_names)
mesh_nodes = [n for n in nodes if "mesh" in n]
assert len(mesh_nodes) == 11 and all(n.get("skin") == 0 for n in mesh_nodes)
assert not doc.get("cameras") and "KHR_lights_punctual" not in doc.get("extensions", {})
assert len(doc["materials"]) == 5 and len(doc["images"]) == 1
image_view = doc["bufferViews"][doc["images"][0]["bufferView"]]
image_bytes = binary[image_view.get("byteOffset", 0):image_view.get("byteOffset", 0) + image_view["byteLength"]]
assert image_bytes[:8] == b"\x89PNG\r\n\x1a\n"
texture_size = struct.unpack_from(">II", image_bytes, 16)
assert texture_size == (512, 512)
texture_hash = hashlib.sha256(image_bytes).hexdigest()
assert texture_hash == "9e7dd3a56fe27e8140b8bb212d5b970701d58b1da77eb881b2a086c28ed31c71"
vertices = triangles = surfaces = 0
for mesh in doc["meshes"]:
    for primitive in mesh["primitives"]:
        attributes = primitive["attributes"]
        assert {"POSITION", "NORMAL", "TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"} <= attributes.keys()
        assert "JOINTS_1" not in attributes and "WEIGHTS_1" not in attributes
        assert not any(k.startswith("COLOR") for k in attributes)
        vertices += doc["accessors"][attributes["POSITION"]]["count"]
        triangles += doc["accessors"][primitive["indices"]]["count"] // 3
        surfaces += 1
assert triangles == 16222
animations = doc.get("animations", [])
assert len(animations) == 1 and animations[0]["name"] == "TEST_v020_POSE_SAMPLES"
assert all(channel["target"]["node"] in skins[0]["joints"] for channel in animations[0]["channels"])
times = [doc["accessors"][s["input"]] for s in animations[0]["samplers"]]
assert all(a["min"] == [0] and a["max"] == [8] for a in times)
for node in nodes:
    assert all(abs(s - 1) < 0.0001 for s in node.get("scale", [1, 1, 1]))
report = {
    "glb_sha256": hashlib.sha256(blob).hexdigest(), "bytes": len(blob),
    "meshes": [n["name"] for n in mesh_nodes], "bones": joint_names,
    "skins": len(skins), "vertices_after_splitting": vertices,
    "triangles": triangles, "primitives": surfaces, "image_count": 1,
    "texture_dimensions": texture_size, "embedded_texture_sha256": texture_hash,
    "materials": doc["materials"], "samplers": doc.get("samplers", []),
    "animation": {"name": animations[0]["name"], "seconds": 8, "channels": len(animations[0]["channels"])},
    "note": "Source mask factor is 0.9 linear RGB; retained exactly. Runtime converts it to sRGB 0.954687.",
    "pass": True,
}
(ROOT / "docs/validation/player-v020/glb_audit.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(f"PASS: GLB / {len(mesh_nodes)} meshes / {len(joint_names)} bones / {triangles} triangles / embedded PNG unchanged")
