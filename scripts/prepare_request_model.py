"""Fit a static Pixal3D candidate to a request; preserve the unchanged raw GLB.

Uses NumPy. Orientation is estimated from mesh bounds and requires art review.
This intentionally rejects rigs, morph targets and transformed/multiple nodes.
"""
import argparse
import hashlib
import itertools
import json
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def load_glb(path):
    raw = path.read_bytes()
    if struct.unpack_from("<4sII", raw) != (b"glTF", 2, len(raw)):
        raise ValueError("Invalid GLB header")
    size, kind = struct.unpack_from("<II", raw, 12)
    if kind != 0x4E4F534A:
        raise ValueError("Missing GLB JSON")
    document = json.loads(raw[20:20 + size])
    offset = 20 + size
    binary_size, binary_kind = struct.unpack_from("<II", raw, offset)
    if binary_kind != 0x004E4942 or offset + 8 + binary_size != len(raw):
        raise ValueError("Expected one embedded binary chunk")
    return document, bytearray(raw[offset + 8:])


def accessor(document, binary, index):
    entry = document["accessors"][index]
    view = document["bufferViews"][entry["bufferView"]]
    widths = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
    types = {5126: "<f4", 5125: "<u4", 5123: "<u2", 5121: "u1"}
    if "sparse" in entry or entry.get("normalized"):
        raise ValueError("Unsupported accessor encoding")
    dtype = np.dtype(types[entry["componentType"]])
    width = widths[entry["type"]]
    return np.ndarray((entry["count"], width), dtype=dtype, buffer=binary,
                      offset=view.get("byteOffset", 0) + entry.get("byteOffset", 0),
                      strides=(view.get("byteStride", dtype.itemsize * width), dtype.itemsize))


def estimate_frame(points, triangles, target):
    centered = points - points.mean(axis=0)
    _, principal = np.linalg.eigh(centered.T @ centered)
    edges_a = points[triangles[:, 1]] - points[triangles[:, 0]]
    edges_b = points[triangles[:, 2]] - points[triangles[:, 0]]
    normals = np.cross(edges_a, edges_b)
    weights = np.linalg.norm(normals, axis=1)
    nonzero = weights > 1e-12
    normals = normals[nonzero] / weights[nonzero, None]
    weights = weights[nonzero]
    # Group broad planar faces; curved parts also retain the PCA candidates.
    normals *= np.where(normals[np.arange(len(normals)), np.argmax(np.abs(normals), axis=1)] < 0, -1, 1)[:, None]
    buckets, inverse = np.unique(np.round(normals, 1), axis=0, return_inverse=True)
    areas = np.bincount(inverse, weights=weights)
    grouped = np.zeros_like(buckets)
    for axis in range(3):
        grouped[:, axis] = np.bincount(inverse, weights=weights * normals[:, axis], minlength=len(buckets))
    grouped /= np.maximum(np.linalg.norm(grouped, axis=1, keepdims=True), 1e-12)
    candidates = np.concatenate((principal.T, grouped[np.argsort(areas)[-24:]]))
    best = principal.T
    best_volume = float("inf")
    for first in candidates:
        for other in candidates:
            second = other - first * np.dot(first, other)
            length = np.linalg.norm(second)
            if length < 0.1:
                continue
            second /= length
            frame = np.array([first, second, np.cross(first, second)])
            projected = points @ frame.T
            extent = np.ptp(projected, axis=0)
            volume = np.prod(extent)
            if volume < best_volume:
                best_volume, best = volume, frame
    # Choose axis order by requested proportions; signs favor source +Y/+Z.
    best_score = float("inf")
    oriented = best
    for order in itertools.permutations(range(3)):
        frame = best[list(order)].copy()
        if frame[1, 1] < 0:
            frame[1] *= -1
        if frame[2, 2] < 0:
            frame[2] *= -1
        if np.linalg.det(frame) < 0:
            frame[0] *= -1
        extent = np.ptp(points @ frame.T, axis=0)
        proportions = np.log(extent / target)
        score = np.sum((proportions - proportions.mean()) ** 2) + 0.08 * (1 - frame[1, 1])
        if score < best_score:
            best_score, oriented = score, frame
    return oriented


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("asset_id")
    parser.add_argument("--folder", help="Parent asset folder for separate parts")
    parser.add_argument("--size", nargs=3, type=float, required=True, metavar=("X", "Y", "Z"))
    parser.add_argument("--origin", choices=["center", "bottom"], default="bottom")
    parser.add_argument("--yaw", type=float, default=0, help="Manual adjustment after reviewing views, degrees")
    parser.add_argument("--offset", nargs=3, type=float, default=[0, 0, 0], help="Requested asymmetric bounds relative to the origin")
    args = parser.parse_args()
    folder = args.folder or args.asset_id
    if not all(name.replace("_", "").isalnum() for name in [folder, args.asset_id]):
        parser.error("Use simple asset names")
    target = np.array(args.size)
    if not np.all(np.isfinite(target)) or np.min(target) <= 0:
        parser.error("Sizes must be finite positive numbers")
    source_dir = ROOT / "art_source" / folder
    source = source_dir / (args.asset_id + "_raw.glb")
    document, binary = load_glb(source)
    nodes = document["nodes"]
    if len(nodes) != 1 or set(nodes[0]) - {"mesh", "name"} or document.get("skins") or document.get("animations"):
        raise ValueError("Only one untransformed static mesh node is supported")
    primitives = document["meshes"][nodes[0]["mesh"]]["primitives"]
    if len(primitives) != 1 or primitives[0].get("mode", 4) != 4 or primitives[0].get("targets"):
        raise ValueError("Only one triangle primitive without morphs is supported")
    primitive = primitives[0]
    attributes = primitive["attributes"]
    positions = accessor(document, binary, attributes["POSITION"])
    points = positions.astype(np.float64)
    triangles = accessor(document, binary, primitive["indices"]).reshape(-1, 3)
    frame = estimate_frame(points, triangles, target)
    yaw = np.deg2rad(args.yaw)
    yaw_matrix = np.array([[np.cos(yaw), 0, np.sin(yaw)], [0, 1, 0], [-np.sin(yaw), 0, np.cos(yaw)]])
    frame = yaw_matrix @ frame
    aligned = points @ frame.T
    extent = np.ptp(aligned, axis=0)
    scale = target / extent
    matrix = np.diag(scale) @ frame
    transformed = points @ matrix.T
    lower, upper = transformed.min(axis=0), transformed.max(axis=0)
    pivot = (lower + upper) / 2
    if args.origin == "bottom":
        pivot[1] = lower[1]
    transformed -= pivot
    transformed += np.array(args.offset)
    positions[:] = transformed
    document["accessors"][attributes["POSITION"]]["min"] = positions.min(axis=0).tolist()
    document["accessors"][attributes["POSITION"]]["max"] = positions.max(axis=0).tolist()
    if "NORMAL" in attributes:
        normals = accessor(document, binary, attributes["NORMAL"])
        adjusted = normals.astype(np.float64) @ np.linalg.inv(matrix)
        adjusted /= np.maximum(np.linalg.norm(adjusted, axis=1, keepdims=True), 1e-12)
        normals[:] = adjusted
    if "TANGENT" in attributes:
        tangents = accessor(document, binary, attributes["TANGENT"])
        adjusted = tangents[:, :3].astype(np.float64) @ matrix.T
        if "NORMAL" in attributes:
            adjusted -= normals * np.sum(adjusted * normals, axis=1, keepdims=True)
        adjusted /= np.maximum(np.linalg.norm(adjusted, axis=1, keepdims=True), 1e-12)
        tangents[:, :3] = adjusted
    node = document["nodes"][0]
    node["name"] = args.asset_id + "_candidate"
    document["asset"]["generator"] = "Pixal3D / ApocalypseRV candidate preparation"
    # Full API workflow is preserved with the raw GLB; omit duplicate metadata.
    document["asset"].pop("extras", None)
    json_bytes = json.dumps(document, separators=(",", ":")).encode()
    json_bytes += b" " * (-len(json_bytes) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    output_bytes = (struct.pack("<4sII", b"glTF", 2, 28 + len(json_bytes) + len(binary))
                    + struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
                    + struct.pack("<II", len(binary), 0x004E4942) + binary)
    destination = ROOT / "assets/models" / folder / (args.asset_id + "_candidate.glb")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(output_bytes)
    report = {
        "raw": str(source.relative_to(ROOT)).replace("\\", "/"),
        "candidate": str(destination.relative_to(ROOT)).replace("\\", "/"),
        "raw_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "candidate_sha256": hashlib.sha256(output_bytes).hexdigest(),
        "triangles": len(triangles), "vertices": len(points),
        "raw_aabb_size": np.ptp(points, axis=0).tolist(), "aligned_extent": extent.tolist(),
        "rotation_rows": frame.tolist(), "scale": scale.tolist(), "pivot": pivot.tolist(),
        "candidate_aabb_min": positions.min(axis=0).tolist(),
        "candidate_aabb_size": np.ptp(positions, axis=0).tolist(),
        "origin": args.origin, "manual_yaw_degrees": args.yaw,
        "offset": args.offset,
        "orientation_method": "estimated oriented bounds; front direction and detailed interfaces require art review",
    }
    (source_dir / (args.asset_id + "_preparation.json")).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
