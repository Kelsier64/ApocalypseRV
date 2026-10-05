import io
import json
import pathlib
import socket
import struct
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import requests
import uvicorn
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from app import create_app
from pipeline import InputError
from service import JobService, ServiceError, artifact_reference, glb_info


def png():
    stream = io.BytesIO()
    Image.new("RGBA", (64, 64), (30, 50, 80, 128)).save(stream, "PNG")
    return stream.getvalue()


def glb():
    data = json.dumps({"asset": {"version": "2.0"}, "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}]}).encode()
    data += b" " * (-len(data) % 4)
    return struct.pack("<4sIII", b"glTF", 2, 20 + len(data), len(data)) + struct.pack("<I", 0x4E4F534A) + data


class Backend:
    url = "http://test-backend.invalid"

    def __init__(self):
        self.submissions = []
        self.uploads = []
        self.graph = None
        self.reference_folder = None
        self.busy = False
        self.fail_history = False

    def health(self):
        return {}

    def queue(self):
        return {"queue_running": [1] if self.busy else [], "queue_pending": []}

    def upload(self, name, data):
        self.uploads.append((name, data))
        return name

    def submit(self, graph, client_id):
        self.graph = graph
        self.submissions.append(client_id)
        return "prompt-1"

    def history(self, prompt_id):
        if self.fail_history:
            raise requests.ConnectionError("secret local path C:\\private\\job")
        folder = self.reference_folder or self.graph["save"]["inputs"]["filename_prefix"].rsplit("/", 1)[0]
        outputs = {"save": {"3d": [{"filename": "model.glb", "subfolder": folder, "type": "output"}]}}
        for node in self.graph:
            if node.startswith("conditioning_"):
                outputs[node] = {"images": [{"filename": "conditioning.png", "subfolder": folder + "/conditioning", "type": "output"}]}
        return {"status": {"status_str": "success", "completed": True}, "outputs": outputs}

    def download(self, reference, max_bytes=None):
        return glb() if reference["filename"].endswith(".glb") else png()


def graph(preset, input_files, metadata, artifact_prefix):
    output = {"save": {"class_type": "SaveGLB", "inputs": {"filename_prefix": artifact_prefix + "/model"}},
              "sampler": {"class_type": "KSampler", "inputs": {"seed": 0}}}
    for view in input_files:
        output["conditioning_" + view] = {"class_type": "SaveImage", "inputs": {"filename_prefix": artifact_prefix + "/conditioning/" + view}}
    return output


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        self.backend = Backend()
        self.service = JobService(self.root, self.backend, poll_interval=0.001, idle_timeout=0.005)
        self.graph_patch = patch("service.build_workflow", graph)
        self.graph_patch.start()

    def tearDown(self):
        self.service.stop()
        self.graph_patch.stop()
        self.temporary.cleanup()

    def submit(self, **kwargs):
        return self.service.submit({"image": png()}, "test_asset", **kwargs)["job_id"]

    def test_idempotency_survives_restart_and_rejects_changed_options(self):
        key = self.submit(idempotency_key="request-1")
        reused = JobService(self.root, self.backend).submit({"image": png()}, "test_asset", idempotency_key="request-1")
        self.assertEqual(reused["job_id"], key)
        self.assertTrue(reused["reused"])
        for options in ({"seed": 43}, {"fov": 20}, {"background": "remove"}, {"preset": "standard1024"}):
            with self.assertRaises(ServiceError) as caught:
                self.submit(idempotency_key="request-1", **options)
            self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual((self.root / "jobs" / key / "originals" / "image.upload").read_bytes(), png())

    def test_input_validation_never_queues(self):
        for options in ({"asset_id": "UPPER"}, {"seed": -1}, {"seed": 2**63}, {"fov": float("nan")}):
            values = {"asset_id": "asset", **options}
            with self.assertRaises((ServiceError, InputError)):
                self.service.submit({"image": png()}, **values)
        with self.assertRaises(InputError):
            self.service.submit({"image": b"not an image"}, "asset")
        self.assertEqual(self.service.pending.qsize(), 0)
        self.assertEqual(self.service.jobs, {})

    def test_snapshot_is_deeply_immutable_and_public_has_no_local_paths(self):
        key = self.submit()
        snapshot = self.service.snapshot(key)
        snapshot["inputs"]["prepared_dimensions"]["image"][0] = -100
        self.assertEqual(self.service.snapshot(key)["inputs"]["prepared_dimensions"]["image"], [64, 64])
        self.assertNotIn(str(self.root), json.dumps(self.service.public_snapshot(key)))
        self.assertNotIn("idempotency_key", self.service.public_snapshot(key))

    def test_queued_restart_uses_saved_inputs_and_completed_download_survives(self):
        key = self.submit(seed=123)
        restarted = JobService(self.root, self.backend)
        self.assertEqual(restarted.pending.qsize(), 1)
        restarted.run_job(key)
        self.assertEqual(self.backend.graph["sampler"]["inputs"]["seed"], 123)
        self.assertEqual(len(self.backend.submissions), 1)
        self.assertEqual(self.backend.uploads[0][1], restarted.input_path(key, "image").read_bytes())
        complete = JobService(self.root, self.backend)
        self.assertEqual(complete.snapshot(key)["state"], "succeeded")
        self.assertEqual(complete.pending.qsize(), 0)
        self.assertEqual(complete.artifact_path(key).read_bytes(), glb())
        self.assertIn("image", complete.result(key)["conditioning"])
        self.assertTrue((self.root / "jobs" / key / "prompt.json").exists())
        self.assertTrue((self.root / "jobs" / key / "history.json").exists())
        complete.artifact_path(key).write_bytes(b"corrupted")
        with self.assertRaises(ServiceError):
            complete.artifact_path(key)

    def test_running_restart_reconciles_prompt_without_resubmission(self):
        key = self.submit()
        self.service._update(key, state="running", prompt_id="prompt-1", started_at=time.time())
        self.backend.graph = graph("preview512", {"image": "x"}, {}, self.service.snapshot(key)["artifact_prefix"])
        restarted = JobService(self.root, self.backend)
        restarted.run_job(key)
        self.assertEqual(restarted.snapshot(key)["state"], "succeeded")
        self.assertEqual(self.backend.submissions, [])
        self.assertEqual(self.backend.uploads, [])

    def test_uncertain_running_restart_fails_without_requeue(self):
        key = self.submit()
        self.service._update(key, state="running")
        restarted = JobService(self.root, self.backend)
        self.assertEqual(restarted.pending.qsize(), 0)
        self.assertEqual(restarted.snapshot(key)["state"], "failed")
        self.assertIn("uncertain", restarted.snapshot(key)["error"])

    def test_backend_failures_keep_prompt_and_do_not_resubmit(self):
        key = self.submit()
        self.backend.fail_history = True
        self.service.start()
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and self.service.snapshot(key)["state"] != "failed":
            time.sleep(0.01)
        failed = self.service.snapshot(key)
        self.assertEqual(failed["state"], "failed")
        self.assertEqual(failed["prompt_id"], "prompt-1")
        self.assertEqual(len(self.backend.submissions), 1)
        self.assertNotIn("private", failed["error"])
        self.assertEqual(JobService(self.root, self.backend).pending.qsize(), 0)

    def test_shared_backend_queue_has_bounded_wait(self):
        key = self.submit()
        self.backend.busy = True
        with self.assertRaises(TimeoutError):
            self.service.run_job(key)
        self.assertEqual(self.backend.submissions, [])

    def test_artifact_references_reject_traversal_and_wrong_output_type(self):
        allowed = "pixal3d-api-v2/jobs/job"
        good = {"filename": "model.glb", "subfolder": allowed, "type": "output"}
        self.assertEqual(artifact_reference(good, allowed), good)
        windows = {**good, "subfolder": allowed.replace("/", "\\")}
        self.assertEqual(artifact_reference(windows, allowed), good)
        nested_windows = {**windows, "subfolder": windows["subfolder"] + "\\conditioning"}
        self.assertEqual(artifact_reference(nested_windows, allowed)["subfolder"], allowed + "/conditioning")
        for changed in ({"filename": "../model.glb"}, {"filename": "C:\\file.glb"}, {"subfolder": allowed + "/../../elsewhere"},
                        {"subfolder": allowed + "-other"}, {"subfolder": "/" + allowed}, {"subfolder": "C:\\output"},
                        {"subfolder": "\\\\server\\share\\" + allowed}, {"subfolder": "\\" + allowed},
                        {"subfolder": allowed + "\\..\\../elsewhere"}, {"subfolder": allowed + "\x00"}, {"type": "input"}):
            with self.assertRaises(ValueError):
                artifact_reference({**good, **changed}, allowed)
        key = self.submit()
        self.backend.reference_folder = "other/job"
        with self.assertRaises(ValueError):
            self.service.run_job(key)
        self.assertFalse((self.root / "jobs" / key / "result.glb").exists())

    def test_glb_container_structure_and_digest(self):
        self.assertEqual(glb_info(glb())["bytes"], len(glb()))
        for data in (b"", glb()[:-1], b"WRNG" + glb()[4:], glb() + b"extra"):
            with self.assertRaises(ValueError):
                glb_info(data)

    def test_missing_or_incorrect_conditioning_cannot_succeed(self):
        key = self.submit()
        original_history = self.backend.history

        def missing(prompt_id):
            history = original_history(prompt_id)
            history["outputs"].pop("conditioning_image")
            return history

        with patch.object(self.backend, "history", missing):
            with self.assertRaisesRegex(ValueError, "Missing required conditioning"):
                self.service.run_job(key)
        self.assertNotEqual(self.service.snapshot(key)["state"], "succeeded")
        self.service._update(key, state="queued", prompt_id=None)
        original_download = self.backend.download

        def wrong_size(reference, max_bytes=None):
            if reference["filename"].endswith(".glb"):
                return original_download(reference)
            stream = io.BytesIO()
            Image.new("RGB", (100, 100)).save(stream, "PNG")
            return stream.getvalue()

        with patch.object(self.backend, "download", wrong_size):
            with self.assertRaisesRegex(ValueError, "Conditioning dimensions"):
                self.service.run_job(key)

    def test_single_conditioning_uses_crop_output_dimensions(self):
        key = self.submit()

        def cropped_graph(preset, input_files, metadata, artifact_prefix):
            output = graph(preset, input_files, metadata, artifact_prefix)
            output["crop"] = {"class_type": "ImageCropToMask", "inputs": {"width": 96, "height": 96}}
            output["conditioning_image"]["inputs"]["images"] = ["crop", 0]
            return output

        original_download = self.backend.download

        def cropped_download(reference, max_bytes=None):
            if reference["filename"].endswith(".glb"):
                return original_download(reference)
            stream = io.BytesIO()
            Image.new("RGB", (96, 96)).save(stream, "PNG")
            return stream.getvalue()

        with patch("service.build_workflow", cropped_graph), patch.object(self.backend, "download", cropped_download):
            self.service.run_job(key)
        self.assertEqual(self.service.result(key)["conditioning_dimensions"], {"image": [96, 96]})

    def legacy(self, **changes):
        key = "12345678-1234-1234-1234-123456789abc"
        legacy_root = self.root / "legacy"
        directory = legacy_root / "jobs" / key
        directory.mkdir(parents=True, exist_ok=True)
        artifact = directory / "result.glb"
        artifact.write_bytes(glb())
        validation = glb_info(glb())
        validation.update(godot_tested=True, blender_tested=False)
        job = {"job_id": key, "asset_id": "legacy_asset", "state": "succeeded", "preset": "threeview512",
               "artifact": str(artifact), "validation": validation, "needs_art_review": True,
               "reference_layout": ["front", "left", "back"], **changes}
        file = directory / "job.json"
        file.write_text(json.dumps(job), encoding="utf-8")
        with patch.dict("os.environ", {"PIXAL3D_LEGACY_ROOT": str(legacy_root)}):
            service = JobService(self.root, self.backend)
        return key, service, file, artifact

    def test_completed_legacy_jobs_are_read_only_and_keep_original_flags(self):
        key, service, file, artifact = self.legacy()
        original_metadata = file.read_bytes()
        original_artifact = artifact.read_bytes()
        self.assertEqual(service.pending.qsize(), 0)
        self.assertEqual(service.jobs, {})
        result = service.result(key)
        self.assertEqual(result["service_revision"], "legacy")
        self.assertFalse(result["framing_verified"])
        self.assertTrue(result["godot_tested"])
        self.assertFalse(result["blender_tested"])
        self.assertEqual(result["conditioning"], {})
        self.assertNotIn("inputs", result)
        self.assertEqual(service.artifact_path(key).read_bytes(), glb())
        self.assertNotIn(str(self.root), json.dumps(service.public_snapshot(key)))
        with self.assertRaises(ServiceError) as caught:
            service.artifact_path(key, "front")
        self.assertEqual(caught.exception.status_code, 404)
        self.assertEqual(file.read_bytes(), original_metadata)
        self.assertEqual(artifact.read_bytes(), original_artifact)

    def test_legacy_path_confinement_digest_and_incomplete_job_filter(self):
        key, service, file, artifact = self.legacy()
        artifact.write_bytes(b"corrupted")
        with self.assertRaises(ServiceError) as caught:
            service.result(key)
        self.assertEqual(caught.exception.status_code, 409)
        outside = self.root / "outside.glb"
        outside.write_bytes(glb())
        key, service, _, _ = self.legacy(artifact=str(outside))
        with self.assertRaises(ServiceError) as caught:
            service.artifact_path(key)
        self.assertEqual(caught.exception.status_code, 404)
        key, service, _, _ = self.legacy(state="running", prompt_id="legacy-prompt")
        with self.assertRaises(ServiceError) as caught:
            service.snapshot(key)
        self.assertEqual(caught.exception.status_code, 404)
        self.assertEqual(service.pending.qsize(), 0)


class HttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.backend = Backend()
        cls.legacy_root = pathlib.Path(cls.temporary.name) / "legacy"
        with patch.dict("os.environ", {"PIXAL3D_LEGACY_ROOT": str(cls.legacy_root)}):
            cls.application = create_app(cls.temporary.name, cls.backend, start_worker=False)
        cls.service = cls.application.state.service
        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        cls.address = "http://127.0.0.1:" + str(sock.getsockname()[1])
        cls.server = uvicorn.Server(uvicorn.Config(cls.application, log_level="error"))
        cls.thread = threading.Thread(target=cls.server.run, kwargs={"sockets": [sock]}, daemon=True)
        cls.thread.start()
        deadline = time.monotonic() + 5
        while not cls.server.started and time.monotonic() < deadline:
            time.sleep(0.01)
        if not cls.server.started:
            raise RuntimeError("Test HTTP server did not start")

    @classmethod
    def tearDownClass(cls):
        cls.server.should_exit = True
        cls.thread.join(timeout=5)
        cls.temporary.cleanup()

    def test_http_legacy_submit_validation_result_and_conditioning(self):
        response = requests.post(self.address + "/jobs", files={"image": ("input.png", png(), "image/png")},
                                 data={"asset_id": "legacy_asset", "seed": "42"}, headers={"Idempotency-Key": "http-1"}, timeout=5)
        self.assertEqual(response.status_code, 202, response.text)
        key = response.json()["job_id"]
        self.assertEqual(requests.get(self.address + f"/jobs/{key}/result", timeout=5).status_code, 409)
        self.assertEqual(requests.get(self.address + f"/jobs/{key}/inputs/image.png", timeout=5).status_code, 200)
        with patch("service.build_workflow", graph):
            self.service.run_job(key)
        result = requests.get(self.address + f"/jobs/{key}/result", timeout=5)
        self.assertEqual(result.status_code, 200, result.text)
        self.assertTrue(result.json()["needs_art_review"])
        self.assertFalse(result.json()["godot_tested"])
        self.assertFalse(result.json()["blender_tested"])
        self.assertEqual(requests.get(self.address + result.json()["download_url"], timeout=5).content, glb())
        self.assertEqual(requests.get(self.address + result.json()["conditioning"]["image"], timeout=5).content, png())
        self.assertEqual(requests.get(self.address + f"/jobs/{key}/conditioning/right.png", timeout=5).status_code, 404)
        self.assertNotIn(self.temporary.name, requests.get(self.address + f"/jobs/{key}", timeout=5).text)
        invalid = requests.post(self.address + "/jobs", files={"image": ("x", png())}, data={"asset_id": "UPPER"}, timeout=5)
        self.assertEqual(invalid.status_code, 422)
        health = requests.get(self.address + "/health", timeout=5).json()
        self.assertEqual(health["service"], "pixal3d-api-v2")
        self.assertEqual(health["version"], "0.2.0")

    def test_http_separate_multiview_route(self):
        files = {view: (view + ".png", png(), "image/png") for view in ("front", "left", "back", "right")}
        response = requests.post(self.address + "/jobs/multiview", files=files, data={"asset_id": "separate", "preset": "threeview512"}, timeout=5)
        self.assertEqual(response.status_code, 202, response.text)
        job = self.service.snapshot(response.json()["job_id"])
        self.assertEqual(job["input_views"], ["front", "left", "back", "right"])
        self.assertEqual(job["fov"], 20.0)
        for dimensions in job["inputs"]["prepared_dimensions"].values():
            self.assertEqual(dimensions, [1024, 1024])
        missing = requests.post(self.address + "/jobs/multiview", files={"front": files["front"]}, data={"asset_id": "missing"}, timeout=5)
        self.assertEqual(missing.status_code, 422)

    def test_http_completed_legacy_inputs_are_explicitly_unavailable(self):
        key = "12345678-1234-1234-1234-123456789abc"
        directory = self.legacy_root / "jobs" / key
        directory.mkdir(parents=True, exist_ok=True)
        artifact = directory / "result.glb"
        artifact.write_bytes(glb())
        job = {"job_id": key, "asset_id": "legacy_asset", "state": "succeeded", "preset": "threeview512",
               "artifact": str(artifact), "validation": glb_info(glb()), "needs_art_review": True}
        metadata = directory / "job.json"
        metadata.write_text(json.dumps(job), encoding="utf-8")
        original = metadata.read_bytes()
        status = requests.get(self.address + f"/jobs/{key}", timeout=5)
        self.assertEqual(status.status_code, 200, status.text)
        self.assertEqual(status.json()["service_revision"], "legacy")
        for endpoint in ("inputs", "inputs/front.png"):
            response = requests.get(self.address + f"/jobs/{key}/{endpoint}", timeout=5)
            self.assertEqual(response.status_code, 404, response.text)
        result = requests.get(self.address + f"/jobs/{key}/result", timeout=5)
        self.assertEqual(result.status_code, 200, result.text)
        self.assertFalse(result.json()["framing_verified"])
        self.assertEqual(requests.get(self.address + result.json()["download_url"], timeout=5).content, glb())
        self.assertEqual(metadata.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
