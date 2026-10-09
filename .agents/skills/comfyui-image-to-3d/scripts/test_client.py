"""Offline client regression checks; no HTTP requests or ComfyUI jobs."""
import io
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

import generate
import review


def png(size=64):
    image = Image.new("RGBA", (size, size), (120, 140, 160, 255))
    image.putpixel((0, 0), (0, 0, 0, 0))
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    return stream.getvalue()


def textured_triangle(attributes=None):
    texture = png()
    binary = struct.pack("<9f3H", 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 2) + b"\0\0" + texture
    doc = {
        "asset": {"version": "2.0"}, "buffers": [{"byteLength": len(binary)}],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36},
                        {"buffer": 0, "byteOffset": 36, "byteLength": 6},
                        {"buffer": 0, "byteOffset": 44, "byteLength": len(texture)}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "type": "VEC3", "count": 3},
                      {"bufferView": 1, "componentType": 5123, "type": "SCALAR", "count": 3}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "material": 0}]}],
        "materials": [{}], "images": [{"bufferView": 2, "mimeType": "image/png"}],
    }
    for semantic, rows in (attributes or {}).items():
        kind, width = {"NORMAL": ("VEC3", 3), "TEXCOORD_0": ("VEC2", 2), "TANGENT": ("VEC4", 4)}[semantic]
        binary += b"\0" * (-len(binary) % 4)
        packed = struct.pack("<" + "f" * width * len(rows), *(v for row in rows for v in row))
        view = len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(packed)})
        doc["meshes"][0]["primitives"][0]["attributes"][semantic] = len(doc["accessors"])
        doc["accessors"].append({"bufferView": view, "componentType": 5126, "type": kind, "count": len(rows)})
        binary += packed
    doc["buffers"][0]["byteLength"] = len(binary)
    encoded = json.dumps(doc).encode()
    encoded += b" " * (-len(encoded) % 4)
    binary += b"\0" * (-len(binary) % 4)
    return (struct.pack("<4sII", b"glTF", 2, 28 + len(encoded) + len(binary))
            + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
            + struct.pack("<II", len(binary), 0x004E4942) + binary)


class Backend:
    def __init__(self, timeout=False, busy=False):
        self.timeout = timeout
        self.busy = busy
        self.posts = []
        self.history = {}
        self.backend = "http://127.0.0.1:8188"

    def preflight(self):
        if self.busy:
            raise RuntimeError("Shared queue is busy")
        return {"backend": self.backend, "state": "READY"}

    def upload(self, data, filename):
        return filename

    def idle(self):
        pass

    def post(self, path, value):
        self.posts.append((path, value))
        if self.timeout:
            raise TimeoutError("reply lost after submission")
        return {"prompt_id": "00000000-0000-0000-0000-000000000001"}

    def get(self, path):
        if path.startswith("/history/"):
            return self.history
        return {"queue_running": [], "queue_pending": []}

    def request(self, base, path):
        return textured_triangle() if ".glb" in path else png(1024)


class ClientTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="comfy-client-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.image = self.root / "reference.png"
        self.image.write_bytes(png())
        self.output = self.root / "job"

    def completed_job(self):
        backend = Backend()
        generate.submit(backend, self.image, self.output, "test_asset")
        job = generate.read(self.output / "job.json")
        backend.history = {job["prompt_id"]: {
            "prompt": [0, job["prompt_id"], generate.read(self.output / "prompt.json"),
                       {"client_id": job["client_id"]}],
            "status": {"status_str": "success", "completed": True},
            "outputs": {"save": {"files": [{"filename": "model.glb", "type": "output"}]},
                        "conditioning_image": {"images": [{"filename": "conditioning.png", "type": "output"}]}},
        }}
        backend.posts.clear()
        return backend, job

    def test_busy_backend_does_not_create_job_or_post(self):
        backend = Backend(busy=True)
        with self.assertRaisesRegex(RuntimeError, "busy"):
            generate.submit(backend, self.image, self.output, "test_asset")
        self.assertFalse(self.output.exists())
        self.assertEqual(backend.posts, [])

    def test_lost_submission_reply_is_durable_and_never_reposted(self):
        backend = Backend(timeout=True)
        with self.assertRaisesRegex(RuntimeError, "uncertain"):
            generate.submit(backend, self.image, self.output, "test_asset")
        self.assertEqual(generate.read(self.output / "job.json")["state"], "SUBMISSION_UNKNOWN")
        self.assertTrue((self.output / "prompt.json").is_file())
        with self.assertRaisesRegex(RuntimeError, "already exists"):
            generate.submit(backend, self.image, self.output, "test_asset")
        self.assertEqual(len(backend.posts), 1)

    def test_saved_reference_and_graph_remain_bound_to_job(self):
        backend, _ = self.completed_job()
        self.assertEqual((self.output / "reference.png").read_bytes(), self.image.read_bytes())
        (self.output / "reference.png").write_bytes(png(65))
        with patch.object(generate, "Client", return_value=backend):
            with self.assertRaisesRegex(ValueError, "hash changed"):
                generate.collect(self.output)
        self.assertFalse((self.output / "raw.glb").exists())
        (self.output / "reference.png").write_bytes(self.image.read_bytes())
        graph = generate.read(self.output / "prompt.json")
        graph["unexpected_node"] = {"class_type": "ModifiedGraph", "inputs": {}}
        generate.save(self.output / "prompt.json", graph)
        with patch.object(generate, "Client", return_value=backend):
            with self.assertRaisesRegex(ValueError, "hash changed"):
                generate.collect(self.output)
        self.assertFalse((self.output / "raw.glb").exists())
        self.assertEqual(backend.posts, [])

    def test_collect_is_read_only_and_repeatable(self):
        backend, _ = self.completed_job()
        with patch.object(generate, "Client", return_value=backend):
            first = generate.collect(self.output)
            original = (self.output / "raw.glb").read_bytes()
            second = generate.collect(self.output)
        self.assertEqual(first, second)
        self.assertEqual(original, (self.output / "raw.glb").read_bytes())
        self.assertEqual(backend.posts, [])
        self.assertFalse(second["art_review_passed"])

    def test_wrong_history_client_is_rejected_before_collection(self):
        backend, job = self.completed_job()
        backend.history[job["prompt_id"]]["prompt"][3]["client_id"] = "another-client"
        with patch.object(generate, "Client", return_value=backend):
            with self.assertRaisesRegex(ValueError, "does not match"):
                generate.collect(self.output)
        self.assertFalse((self.output / "raw.glb").exists())
        self.assertEqual(backend.posts, [])

    def test_collection_preserves_existing_different_artifact(self):
        backend, _ = self.completed_job()
        previous = b"preserve existing raw model"
        (self.output / "raw.glb").write_bytes(previous)
        with patch.object(generate, "Client", return_value=backend):
            with self.assertRaisesRegex(ValueError, "differs"):
                generate.collect(self.output)
        self.assertEqual((self.output / "raw.glb").read_bytes(), previous)

    def test_pose_rejects_scaling_and_reflection(self):
        pose = self.root / "pose.json"
        for rows in ([[2, 0, 0], [0, 1, 0], [0, 0, 1]],
                     [[-1, 0, 0], [0, 1, 0], [0, 0, 1]]):
            generate.save(pose, {"rotation_rows": rows})
            with self.assertRaises(ValueError):
                review.rigid_pose(pose)

    def test_collect_reports_zero_tangent_without_losing_raw_or_resubmitting(self):
        backend, _ = self.completed_job()
        glb = textured_triangle({"NORMAL": [(0, 0, 1)] * 3,
                                "TEXCOORD_0": [(0, 0), (1, 0), (0, 1)],
                                "TANGENT": [(0, 0, 0, 1), (1, 0, 0, 1), (1, 0, 0, 1)]})
        with patch.object(backend, "request", side_effect=lambda base, path: glb if ".glb" in path else png(1024)):
            with patch.object(generate, "Client", return_value=backend):
                result = generate.collect(self.output)
        self.assertEqual((self.output / "raw.glb").read_bytes(), glb)
        self.assertEqual(result["technical_checks"]["attribute_issues"]["zero_tangents"], 1)
        self.assertEqual(result["state"], "ART_REVIEW_REQUIRED")
        self.assertFalse(result["art_review_passed"])
        self.assertFalse(result["technical_checks"]["topology_checked"])
        self.assertEqual(backend.posts, [])

    def test_inspect_rejects_nonfinite_vertex_attributes(self):
        for semantic, bad in (("NORMAL", (float("nan"), 0, 1)),
                              ("TEXCOORD_0", (0, float("inf"))),
                              ("TANGENT", (1, 0, 0, float("nan")))):
            with self.subTest(semantic=semantic):
                with self.assertRaisesRegex(ValueError, "Non-finite.*" + semantic):
                    generate.inspect_glb(textured_triangle({semantic: [bad] * 3}))

    def test_inspect_rejects_mismatched_attribute_count(self):
        with self.assertRaisesRegex(ValueError, "mismatched.*NORMAL"):
            generate.inspect_glb(textured_triangle({"NORMAL": [(0, 0, 1)] * 2}))

    def test_inspect_reports_invalid_normal_tangent_frames(self):
        result = generate.inspect_glb(textured_triangle({
            "NORMAL": [(0, 0, 0), (0, 0, 2), (0, 0, 1)],
            "TANGENT": [(0, 0, 0, 1), (0, 0, 1, 0), (2, 0, 0, -1)]}))
        self.assertEqual(result["attribute_issues"], {
            "zero_normals": 1, "non_unit_normals": 2, "zero_tangents": 1,
            "non_unit_tangents": 2, "non_orthogonal_tangents": 1, "invalid_tangent_handedness": 1})


if __name__ == "__main__":
    unittest.main()
