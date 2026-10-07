"""Package the selected reduced asset, or rebuild its high-poly baseline (--high).

Run with Python from any directory. The editable glTF is also importable in Blender.
The raw model has one identity node and a crankshaft along Z, service face +X.
Bake a -90 degree Y rotation only for raw; fit dimensions and bottom-center origin.
"""
import argparse
import copy
import hashlib
import json
import math
import shutil
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
WORK = ROOT / ".godot/art-work/bunker_diesel_generator/rebuild"
TARGET = (3.20, 1.70, 1.20)


def normalized(v):
    length = math.sqrt(sum(x * x for x in v))
    if length < 1e-12:
        raise ValueError("Degenerate direction")
    return tuple(x / length for x in v)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--high", action="store_true", help="Build the high baseline in the ignored workspace; do not change game delivery")
    parser.add_argument("--gltfpack", help="Path to official gltfpack 1.3, required when rebuilding the reduction")
    args = parser.parse_args()
    source = HERE / "raw.glb" if args.high else WORK / "gltfpack_20k/candidate.glb"
    dest = WORK / "fitted_49k" if args.high else ROOT / "assets/models/bunker_diesel_generator"
    if not args.high and not source.is_file():
        tool = args.gltfpack or shutil.which("gltfpack") or ROOT / ".godot/gltfpack-1.3/bin/gltfpack.exe"
        if not Path(tool).is_file():
            raise SystemExit("Rebuild requires gltfpack 1.3; supply --gltfpack <executable>. No tool is installed automatically.")
        help_result = subprocess.run([str(tool), "-h"], capture_output=True, text=True)
        if not (help_result.stdout + help_result.stderr).startswith("gltfpack 1.3\n"):
            raise SystemExit("This recorded reduction requires gltfpack 1.3")
        subprocess.run([sys.executable, "-B", str(Path(__file__).resolve()), "--high"], check=True)
        source.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([str(tool), "-i", str(WORK / "fitted_49k/source.glb"), "-o", str(source),
                        "-si", "0.4", "-se", "0.01", "-sp", "-sv", "-noq", "-kn", "-km",
                        "-r", str(source.parent / "report.json")], check=True)
    editable_dir = dest / "editable" if args.high else HERE / "editable"
    original = source.read_bytes()
    expected_source = ("34a0f1f5cfa865acfa07970ceda8199ff77e2264662350cb108fd04887007b8c" if args.high
                       else "2d0267dda6918fb41c47a18940267ca7f9767fbe55f0a03aba7df883dbe115f3")
    assert hashlib.sha256(original).hexdigest() == expected_source, "Rebuild input differs from the recorded source"
    assert struct.unpack_from("<4sII", original) == (b"glTF", 2, len(original))
    length = struct.unpack_from("<I", original, 12)[0]
    doc = json.loads(original[20:20 + length])
    binary = bytearray(original[28 + length:])
    assert len(doc["nodes"]) == 1 and doc["nodes"][0].get("mesh") == 0
    assert not any(k in doc["nodes"][0] for k in ("matrix", "translation", "rotation", "scale"))
    assert len(doc["meshes"]) == 1 and len(doc["meshes"][0]["primitives"]) == 1
    primitive = doc["meshes"][0]["primitives"][0]
    assert primitive.get("mode", 4) == 4

    def layout(semantic):
        accessor = doc["accessors"][primitive["attributes"][semantic]]
        view = doc["bufferViews"][accessor["bufferView"]]
        assert accessor["componentType"] == 5126 and not accessor.get("sparse")
        n = {"VEC3": 3, "VEC4": 4}[accessor["type"]]
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return accessor, start, view.get("byteStride", 4 * n), n

    def read_vectors(semantic):
        acc, start, stride, n = layout(semantic)
        return [struct.unpack_from("<" + "f" * n, binary, start + i * stride) for i in range(acc["count"])]

    def write_vectors(semantic, rows):
        acc, start, stride, n = layout(semantic)
        assert len(rows) == acc["count"]
        for i, row in enumerate(rows):
            assert all(math.isfinite(x) for x in row)
            struct.pack_into("<" + "f" * n, binary, start + i * stride, *row)
        if semantic == "POSITION":
            acc["min"] = [min(p[i] for p in rows) for i in range(3)]
            acc["max"] = [max(p[i] for p in rows) for i in range(3)]

    def rotate(v):
        return (-v[2], v[1], v[0]) if args.high else tuple(v)

    points = [rotate(v) for v in read_vectors("POSITION")]
    low = tuple(min(p[i] for p in points) for i in range(3))
    high = tuple(max(p[i] for p in points) for i in range(3))
    source_size = tuple(high[i] - low[i] for i in range(3))
    scale = tuple(TARGET[i] / source_size[i] for i in range(3))
    pivot = ((low[0] + high[0]) / 2, low[1], (low[2] + high[2]) / 2)
    write_vectors("POSITION", [tuple((p[i] - pivot[i]) * scale[i] for i in range(3)) for p in points])
    normals = [normalized(tuple(rotate(v)[i] / scale[i] for i in range(3))) for v in read_vectors("NORMAL")]
    write_vectors("NORMAL", normals)
    tangents = []
    for normal, tangent in zip(normals, read_vectors("TANGENT")):
        t = tuple(rotate(tangent[:3])[i] * scale[i] for i in range(3))
        dot = sum(t[i] * normal[i] for i in range(3))
        t = normalized(tuple(t[i] - dot * normal[i] for i in range(3)))
        tangents.append((*t, tangent[3]))
    write_vectors("TANGENT", tangents)
    doc["asset"]["generator"] = ("TRELLIS.2; ApocalypseRV refine.py (baked metric coordinates)" if args.high
                                 else "TRELLIS.2; gltfpack 1.3; ApocalypseRV refine.py (metric refit)")
    doc["nodes"][0]["name"] = "BunkerDieselGenerator"
    doc["meshes"][0]["name"] = "DieselGeneratorMesh"
    doc["materials"][0]["name"] = "AgedMilitarySteel"
    dest.mkdir(parents=True, exist_ok=True)
    editable_dir.mkdir(parents=True, exist_ok=True)
    names = ("basecolor", "orm", "normal")
    image_hashes = {}
    for entry, name in zip(doc["images"], names):
        view = doc["bufferViews"][entry["bufferView"]]
        start = view.get("byteOffset", 0)
        data = bytes(binary[start:start + view["byteLength"]])
        filename = "bunker_diesel_generator_" + name + ".png"
        (dest / filename).write_bytes(data)
        (editable_dir / filename).write_bytes(data)
        image_hashes[name] = hashlib.sha256(data).hexdigest()
        entry["name"] = name
    packed_json = json.dumps(doc, separators=(",", ":")).encode()
    packed_json += b" " * (-len(packed_json) % 4)
    packed_binary = bytes(binary) + b"\0" * (-len(binary) % 4)
    final = (struct.pack("<4sII", b"glTF", 2, 28 + len(packed_json) + len(packed_binary))
             + struct.pack("<II", len(packed_json), 0x4E4F534A) + packed_json
             + struct.pack("<II", len(packed_binary), 0x004E4942) + packed_binary)
    (dest / ("source.glb" if args.high else "bunker_diesel_generator.glb")).write_bytes(final)
    editable = copy.deepcopy(doc)
    editable["buffers"][0]["uri"] = "bunker_diesel_generator.bin"
    (editable_dir / "bunker_diesel_generator.bin").write_bytes(binary)
    for entry, name in zip(editable["images"], names):
        del entry["bufferView"]
        entry["uri"] = "bunker_diesel_generator_" + name + ".png"
    (editable_dir / "bunker_diesel_generator.gltf").write_text(json.dumps(editable, indent=2) + "\n", encoding="utf-8")
    metadata = {"source_sha256": hashlib.sha256(original).hexdigest(),
                "source": source.relative_to(ROOT).as_posix(),
                "final_sha256": hashlib.sha256(final).hexdigest(),
                "rotation_y_degrees": -90 if args.high else 0, "source_rotated_size": source_size,
                "fit_scale_xyz": scale, "target_size_m": TARGET,
                "origin": "bottom center", "crankshaft": "+/-X", "service_face": "+Z",
                "texture_sha256": image_hashes,
                "geometry_edits": "rotation, per-axis scale and translation baked; inverse-transpose normals; orthogonalized tangents",
                "topology_changed_in_this_fit": False, "textures_changed": False,
                "raw_to_delivery_topology_changed": not args.high,
                "limitations": ["Generated belt-cage perforations are mostly texture relief, not open mesh holes.",
                                "Generated underside/back detail is approximate; no mechanical animation or precision interface."]}
    (dest / "refinement.json" if args.high else HERE / "refinement.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    assert source.read_bytes() == original
    print(json.dumps(metadata))


if __name__ == "__main__":
    main()
