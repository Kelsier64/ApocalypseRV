"""Persistent serial job execution for the local Pixal3D V2 API."""
import copy
import hashlib
import json
import os
import pathlib
import queue
import re
import struct
import threading
import time
import uuid

import requests

from pipeline import InputError, build_workflow, prepare_inputs

VIEWS = frozenset(("image", "front", "left", "back", "right"))
PRESETS = frozenset(("preview512", "standard1024", "threeview512", "threeview1024"))
MAX_IMAGE_BYTES = 25 * 1024 * 1024
MAX_TOTAL_BYTES = 100 * 1024 * 1024


class ServiceError(Exception):
    def __init__(self, status_code, detail):
        super().__init__(str(detail))
        self.status_code, self.detail = status_code, detail


class WorkerStopped(Exception):
    pass


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def glb_info(data):
    """Check container integrity; this is not a geometry or engine review."""
    if len(data) < 20:
        raise ValueError("Truncated GLB")
    magic, version, length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ValueError("Invalid GLB header")
    offset, chunks = 12, []
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("Truncated GLB chunk header")
        size, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        if size % 4 or offset + size > len(data):
            raise ValueError("Invalid GLB chunk length")
        chunks.append((kind, data[offset:offset + size]))
        offset += size
    if not chunks or chunks[0][0] != 0x4E4F534A:
        raise ValueError("Missing GLB JSON chunk")
    if len(chunks) > 2 or (len(chunks) == 2 and chunks[1][0] != 0x004E4942):
        raise ValueError("Unexpected GLB chunks")
    document = json.loads(chunks[0][1].decode("utf-8"))
    if not isinstance(document, dict) or document.get("asset", {}).get("version") != "2.0":
        raise ValueError("Invalid glTF document version")
    meshes = document.get("meshes", [])
    if not meshes or not any(mesh.get("primitives") for mesh in meshes):
        raise ValueError("GLB contains no mesh primitives")
    buffers = document.get("buffers", [])
    for buffer in buffers:
        size = buffer.get("byteLength")
        if not isinstance(size, int) or size < 0:
            raise ValueError("Invalid GLB buffer length")
        if "uri" not in buffer and (len(chunks) < 2 or not size <= len(chunks[1][1]) <= size + 3):
            raise ValueError("GLB binary buffer length mismatch")
    return {"format": "glTF 2.0", "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(), "meshes": len(meshes),
            "materials": len(document.get("materials", [])), "images": len(document.get("images", [])),
            "container_validated": True, "godot_tested": False, "blender_tested": False}


def artifact_reference(item, artifact_prefix):
    """Comfy history is untrusted, including Windows path syntax."""
    filename, folder = item.get("filename"), item.get("subfolder", "")
    if item.get("type") != "output" or not isinstance(filename, str) or not isinstance(folder, str):
        raise ValueError("Unexpected backend artifact reference")
    if not filename or filename in (".", "..") or re.search(r"[\\/:\x00]", filename):
        raise ValueError("Invalid backend artifact filename")
    if re.search(r"[:\x00]", folder):
        raise ValueError("Invalid backend artifact folder")
    # Windows Comfy emits relative subfolders with native separators. Convert
    # them before checking absoluteness and traversal; UNC/rooted paths still
    # become absolute POSIX paths and are rejected below.
    folder = folder.replace("\\", "/")
    path = pathlib.PurePosixPath(folder)
    allowed = pathlib.PurePosixPath(artifact_prefix)
    if path.is_absolute() or ".." in path.parts or path != allowed and allowed not in path.parents:
        raise ValueError("Backend artifact is outside this job")
    return {"filename": filename, "subfolder": folder, "type": "output"}


class ComfyBackend:
    def __init__(self, url):
        self.url = url.rstrip("/")
        self.session = requests.Session()

    def _get(self, path, timeout=30):
        response = self.session.get(self.url + path, timeout=timeout)
        response.raise_for_status()
        return response.json()

    def health(self):
        return self._get("/system_stats", 5)

    def queue(self):
        return self._get("/queue", 10)

    def history(self, prompt_id):
        return self._get("/history/" + prompt_id).get(prompt_id)

    def upload(self, name, data):
        response = self.session.post(self.url + "/upload/image", files={"image": (name, data, "image/png")}, timeout=60)
        response.raise_for_status()
        result = response.json()
        filename, folder = result["name"], result.get("subfolder", "")
        if not isinstance(filename, str) or re.search(r"[\\/:\x00]", filename) or filename in ("", ".", ".."):
            raise ValueError("Invalid backend uploaded image name")
        if not isinstance(folder, str) or re.search(r"[\\:\x00]", folder) or pathlib.PurePosixPath(folder).is_absolute() or ".." in pathlib.PurePosixPath(folder).parts:
            raise ValueError("Invalid backend uploaded image folder")
        return (folder + "/" if folder else "") + filename

    def submit(self, graph, client_id):
        response = self.session.post(self.url + "/prompt", json={"prompt": graph, "client_id": client_id}, timeout=60)
        response.raise_for_status()
        prompt_id = response.json()["prompt_id"]
        if not isinstance(prompt_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", prompt_id):
            raise ValueError("Invalid backend prompt identifier")
        return prompt_id

    def download(self, reference, max_bytes=1024 * 1024 * 1024):
        with self.session.get(self.url + "/view", params=reference, timeout=60, stream=True) as response:
            response.raise_for_status()
            output = bytearray()
            for chunk in response.iter_content(1024 * 1024):
                output.extend(chunk)
                if len(output) > max_bytes:
                    raise ValueError("Backend artifact exceeds download limit")
            return bytes(output)


class JobService:
    def __init__(self, root, backend=None, *, poll_interval=2, idle_timeout=3600, generation_timeout=3600):
        self.root = pathlib.Path(root).resolve()
        legacy = os.environ.get("PIXAL3D_LEGACY_ROOT")
        self.legacy_root = pathlib.Path(legacy).resolve() if legacy else None
        self.job_root = self.root / "jobs"
        self.job_root.mkdir(parents=True, exist_ok=True)
        self.backend = ComfyBackend(backend or os.environ.get("PIXAL3D_COMFY", "http://127.0.0.1:8188")) if isinstance(backend, (str, type(None))) else backend
        self.poll_interval, self.idle_timeout, self.generation_timeout = poll_interval, idle_timeout, generation_timeout
        self.lock = threading.RLock()
        self.pending = queue.Queue()
        self.jobs = {}
        self.idempotency = {}
        self.stop_event = threading.Event()
        self.thread = None
        self._load()

    def _directory(self, job_id):
        return self.job_root / job_id

    def _persist(self, job):
        atomic_json(self._directory(job["job_id"]) / "job.json", job)

    def _update(self, job_id, **fields):
        with self.lock:
            job = self.jobs[job_id]
            job.update(fields, updated_at=time.time())
            self._persist(job)

    def _load(self):
        for file in sorted(self.job_root.glob("*/job.json")):
            job = json.loads(file.read_text(encoding="utf-8"))
            key = job.get("job_id")
            if not isinstance(key, str) or not re.fullmatch(r"[0-9a-f-]{36}", key) or file.parent.name != key:
                raise ValueError("Invalid persisted job identifier")
            self.jobs[key] = job
            token = job.get("idempotency_key")
            if token:
                if token in self.idempotency:
                    raise ValueError("Duplicate persisted idempotency key")
                self.idempotency[token] = key
            if job["state"] == "queued" or job["state"] == "running" and job.get("prompt_id"):
                self.pending.put(key)
            elif job["state"] == "running":
                self._update(key, state="failed", finished_at=time.time(),
                             error="API restarted during submission without a recorded prompt_id. Backend state is uncertain; inspect ComfyUI before retrying.")

    def submit(self, raw_images, asset_id, preset="preview512", seed=42, fov=None, background="auto", idempotency_key=None):
        if not isinstance(asset_id, str) or not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", asset_id):
            raise ServiceError(422, "asset_id must be 1-64 lowercase letters, numbers, underscores or hyphens")
        if not isinstance(seed, int) or isinstance(seed, bool) or not 0 <= seed <= 2**63 - 1:
            raise ServiceError(422, "seed must be between 0 and 2^63-1")
        if preset not in PRESETS:
            raise ServiceError(422, "Unknown preset")
        if not raw_images or set(raw_images) - VIEWS:
            raise ServiceError(422, "Invalid input views")
        if any(len(data) > MAX_IMAGE_BYTES for data in raw_images.values()) or sum(map(len, raw_images.values())) > MAX_TOTAL_BYTES:
            raise ServiceError(413, "Each image must be at most 25 MiB; total uploads must be at most 100 MiB")
        if idempotency_key is not None and (not idempotency_key.strip() or len(idempotency_key) > 256):
            raise ServiceError(422, "Idempotency key must contain 1-256 characters")
        prepared = prepare_inputs(raw_images, preset, fov=fov, background=background)
        prepared_hashes = {view: hashlib.sha256(data).hexdigest() for view, data in prepared.images.items()}
        configuration = {"asset_id": asset_id, "preset": preset, "seed": seed, "requested_fov": fov,
                         "background": background, "prepared_sha256": prepared_hashes, "metadata": prepared.metadata}
        digest = hashlib.sha256(json.dumps(configuration, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()
        with self.lock:
            if idempotency_key and idempotency_key in self.idempotency:
                old = self.jobs[self.idempotency[idempotency_key]]
                if old["request_hash"] != digest:
                    raise ServiceError(409, "Idempotency key already used for a different request")
                return {"job_id": old["job_id"], "state": old["state"], "reused": True}
            key = str(uuid.uuid4())
            directory = self._directory(key)
            (directory / "inputs").mkdir(parents=True)
            (directory / "originals").mkdir()
            for view, data in prepared.images.items():
                if view not in VIEWS:
                    raise ValueError("Pipeline returned an invalid view")
                (directory / "inputs" / (view + ".png")).write_bytes(data)
            for view, data in raw_images.items():
                (directory / "originals" / (view + ".upload")).write_bytes(data)
            now = time.time()
            job = {"job_id": key, "asset_id": asset_id, "preset": preset, "seed": seed,
                   "state": "queued", "created_at": now, "updated_at": now,
                   "idempotency_key": idempotency_key, "request_hash": digest,
                   "inputs": copy.deepcopy(prepared.metadata), "input_views": list(prepared.images),
                   "prepared_sha256": prepared_hashes, "fov": prepared.metadata.get("fov"),
                   "artifact_prefix": "pixal3d-api-v2/jobs/" + key,
                   "needs_art_review": True, "godot_tested": False, "blender_tested": False}
            if prepared.metadata.get("mode") == "multiview":
                job.update(num_views=len(prepared.images), reference_layout=list(prepared.images))
            self._persist(job)
            self.jobs[key] = job
            if idempotency_key:
                self.idempotency[idempotency_key] = key
            self.pending.put(key)
            return {"job_id": key, "state": "queued"}

    def snapshot(self, job_id):
        with self.lock:
            if job_id in self.jobs:
                return copy.deepcopy(self.jobs[job_id])
        return self._legacy_snapshot(job_id)

    def _legacy_snapshot(self, job_id):
        if not self.legacy_root or not re.fullmatch(r"[0-9a-f-]{36}", job_id):
            raise ServiceError(404, "Unknown job")
        file = (self.legacy_root / "jobs" / job_id / "job.json").resolve()
        if not file.is_relative_to(self.legacy_root) or not file.is_file():
            raise ServiceError(404, "Unknown job")
        try:
            job = json.loads(file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            raise ServiceError(404, "Legacy job metadata is unavailable")
        if job.get("job_id") != job_id or job.get("state") != "succeeded":
            raise ServiceError(404, "Unknown completed job")
        job["_legacy"] = True
        return job

    def _legacy_artifact(self, job):
        artifact = job.get("artifact")
        if not isinstance(artifact, str):
            raise ServiceError(404, "Legacy GLB is unavailable")
        path = pathlib.Path(artifact).resolve()
        allowed = (self.legacy_root / "jobs" / job["job_id"]).resolve()
        if not allowed.is_relative_to(self.legacy_root) or not path.is_relative_to(allowed) or path.suffix.lower() != ".glb" or not path.is_file():
            raise ServiceError(404, "Legacy GLB is unavailable")
        expected = job.get("validation", {}).get("sha256")
        try:
            actual = glb_info(path.read_bytes())["sha256"]
        except (OSError, ValueError, TypeError, KeyError):
            raise ServiceError(409, "Legacy GLB failed its integrity check")
        if not isinstance(expected, str) or actual != expected:
            raise ServiceError(409, "Legacy GLB failed its integrity check")
        return path

    def public_snapshot(self, job_id):
        job = self.snapshot(job_id)
        if job.get("_legacy"):
            # Old API metadata has a local artifact field; explicitly select
            # its original public fields instead of exposing arbitrary data.
            allowed = ("job_id", "asset_id", "preset", "seed", "state", "created_at", "updated_at",
                       "started_at", "finished_at", "elapsed_seconds", "prompt_id", "client_id", "validation",
                       "needs_art_review", "godot_tested", "blender_tested", "num_views", "reference_layout", "fov")
            public = {field: job[field] for field in allowed if field in job}
            public.update(service_revision="legacy", framing_verified=False)
            return public
        for field in ("idempotency_key", "request_hash", "artifact_prefix", "prepared_sha256"):
            job.pop(field, None)
        return job

    def input_path(self, job_id, view):
        job = self.snapshot(job_id)
        if view not in VIEWS or view not in job.get("input_views", []):
            raise ServiceError(404, "Input view is unavailable")
        path = self._directory(job_id) / "inputs" / (view + ".png")
        if not path.is_file():
            raise ServiceError(404, "Input view is unavailable")
        return path

    def result(self, job_id):
        job = self.snapshot(job_id)
        if job.get("_legacy"):
            self._legacy_artifact(job)
            validation = job.get("validation", {})
            return {"job_id": job_id, "download_url": f"/jobs/{job_id}/result.glb", "validation": validation,
                    "needs_art_review": job.get("needs_art_review", True),
                    "godot_tested": job.get("godot_tested", validation.get("godot_tested", False)),
                    "blender_tested": job.get("blender_tested", validation.get("blender_tested", False)),
                    "service_revision": "legacy", "framing_verified": False, "conditioning": {}}
        if job["state"] != "succeeded":
            raise ServiceError(409, {"state": job["state"], "error": job.get("error")})
        return {"job_id": job_id, "download_url": f"/jobs/{job_id}/result.glb",
                "validation": job["validation"], "conditioning": {view: f"/jobs/{job_id}/conditioning/{view}.png" for view in job.get("conditioning_views", [])},
                "inputs": job["inputs"], "conditioning_dimensions": job.get("conditioning_dimensions", {}),
                "needs_art_review": True, "godot_tested": False, "blender_tested": False}

    def artifact_path(self, job_id, view=None):
        job = self.snapshot(job_id)
        if job.get("_legacy"):
            if view is not None:
                raise ServiceError(404, "Legacy jobs have no V2 conditioning evidence")
            return self._legacy_artifact(job)
        if view is not None and (view not in VIEWS or view not in job.get("conditioning_views", [])):
            raise ServiceError(404, "Conditioning view is unavailable")
        if job["state"] != "succeeded":
            raise ServiceError(409, "Job has no successful result")
        path = self._directory(job_id) / ("result.glb" if view is None else "conditioning/" + view + ".png")
        if not path.is_file():
            raise ServiceError(404, "Artifact is unavailable")
        if view is None and hashlib.sha256(path.read_bytes()).hexdigest() != job["validation"]["sha256"]:
            raise ServiceError(409, "Stored GLB failed its integrity check")
        return path

    def health(self):
        with self.lock:
            active = sum(job["state"] == "running" for job in self.jobs.values())
            queued = sum(job["state"] == "queued" for job in self.jobs.values())
        try:
            self.backend.health()
            available = True
        except (requests.RequestException, ValueError, OSError):
            available = False
        return {"status": "ready" if available else "degraded", "service": "pixal3d-api-v2", "version": "0.2.0",
                "active": active, "queued": queued, "backend": {"url": getattr(self.backend, "url", None), "available": available}}

    def start(self):
        if self.thread and self.thread.is_alive():
            return
        self.stop_event.clear()
        self.thread = threading.Thread(target=self._worker, name="pixal3d-v2-worker", daemon=True)
        self.thread.start()

    def stop(self):
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=2)

    def _wait(self):
        if self.stop_event.wait(self.poll_interval):
            raise WorkerStopped()

    def _wait_idle(self):
        deadline = time.monotonic() + self.idle_timeout
        while time.monotonic() < deadline:
            if self.stop_event.is_set():
                raise WorkerStopped()
            state = self.backend.queue()
            if not state.get("queue_running") and not state.get("queue_pending"):
                return
            self._wait()
        raise TimeoutError("Timed out waiting for the shared ComfyUI queue to become idle")

    def _worker(self):
        while not self.stop_event.is_set():
            try:
                key = self.pending.get(timeout=0.25)
            except queue.Empty:
                continue
            try:
                self.run_job(key)
            except WorkerStopped:
                return
            except Exception as error:
                # Do not disclose backend URLs, filesystem paths, or exception payloads.
                detail = str(error) if isinstance(error, (ValueError, TimeoutError)) else "Backend or storage operation failed (" + type(error).__name__ + "). Inspect the saved job history and ComfyUI before retrying."
                self._update(key, state="failed", error=detail, finished_at=time.time())
            finally:
                self.pending.task_done()

    def run_job(self, job_id):
        job = self.snapshot(job_id)
        if job["state"] == "queued":
            self._wait_idle()
            self._update(job_id, state="running", started_at=time.time())
            job = self.snapshot(job_id)
            uploaded = {}
            for view in job["input_views"]:
                data = self.input_path(job_id, view).read_bytes()
                if hashlib.sha256(data).hexdigest() != job["prepared_sha256"][view]:
                    raise ValueError("Prepared input failed its integrity check")
                uploaded[view] = self.backend.upload(job_id + "_" + view + ".png", data)
            graph = build_workflow(job["preset"], uploaded, job["inputs"], job["artifact_prefix"])
            for node in graph.values():
                if node.get("class_type") == "KSampler":
                    node["inputs"]["seed"] = job["seed"]
            atomic_json(self._directory(job_id) / "prompt.json", graph)
            client_id = str(uuid.uuid4())
            self._update(job_id, client_id=client_id)
            if self.stop_event.is_set():
                raise WorkerStopped()
            prompt_id = self.backend.submit(graph, client_id)
            self._update(job_id, prompt_id=prompt_id)
            job = self.snapshot(job_id)
        elif job["state"] != "running" or not job.get("prompt_id"):
            return
        # A running job always resumes this prompt; never upload or submit again.
        started = job.get("started_at", time.time())
        deadline = time.monotonic() + self.generation_timeout
        while time.monotonic() < deadline:
            if self.stop_event.is_set():
                raise WorkerStopped()
            history = self.backend.history(job["prompt_id"])
            if history:
                atomic_json(self._directory(job_id) / "history.json", history)
                status = history.get("status", {})
                if status.get("status_str") == "error":
                    raise ValueError("ComfyUI execution failed; inspect the saved history for details")
                if status.get("status_str") == "success" and status.get("completed", True):
                    self._save_outputs(job, history)
                    self._update(job_id, state="succeeded", finished_at=time.time(), elapsed_seconds=time.time() - started)
                    return
            self._wait()
        raise TimeoutError("Generation exceeded its polling timeout. Backend may still be running; inspect ComfyUI before retrying.")

    def _save_outputs(self, job, history):
        outputs = history.get("outputs", {})
        references = outputs.get("save", {}).get("3d", [])
        candidates = [artifact_reference(item, job["artifact_prefix"]) for item in references]
        candidates = [item for item in candidates if item["filename"].lower().endswith(".glb")]
        if len(candidates) != 1:
            raise ValueError("Expected exactly one GLB from the save node")
        data = self.backend.download(candidates[0])
        validation = glb_info(data)
        directory = self._directory(job["job_id"])
        (directory / "result.glb").write_bytes(data)
        conditioning = []
        conditioning_dimensions = {}
        graph = json.loads((directory / "prompt.json").read_text(encoding="utf-8")) if (directory / "prompt.json").exists() else {}
        for view in job["input_views"]:
            images = outputs.get("conditioning_" + view, {}).get("images", [])
            if not images:
                raise ValueError("Missing required conditioning image for " + view)
            if len(images) != 1:
                raise ValueError("Expected one conditioning image per view")
            reference = artifact_reference(images[0], job["artifact_prefix"] + "/conditioning")
            image_data = self.backend.download(reference, max_bytes=MAX_TOTAL_BYTES)
            from PIL import Image
            import io
            with Image.open(io.BytesIO(image_data)) as image:
                if image.format != "PNG":
                    raise ValueError("Conditioning artifact is not PNG")
                expected = job["inputs"]["prepared_dimensions"][view]
                if job["inputs"]["mode"] == "single":
                    link = graph.get("conditioning_" + view, {}).get("inputs", {}).get("images")
                    producer = graph.get(link[0], {}) if isinstance(link, list) and len(link) == 2 else {}
                    sizing = producer.get("inputs", {})
                    if isinstance(sizing.get("width"), int) and isinstance(sizing.get("height"), int):
                        expected = [sizing["width"], sizing["height"]]
                if list(image.size) != list(expected):
                    raise ValueError("Conditioning dimensions do not match the expected canvas for " + view)
                conditioning_dimensions[view] = list(image.size)
                image.verify()
            (directory / "conditioning").mkdir(exist_ok=True)
            (directory / "conditioning" / (view + ".png")).write_bytes(image_data)
            conditioning.append(view)
        self._update(job["job_id"], validation=validation, conditioning_views=conditioning,
                     conditioning_dimensions=conditioning_dimensions)
