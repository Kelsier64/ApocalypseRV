"""Pinned single-image ComfyUI client: one submit, resumable read-only collection."""
import argparse
import hashlib
import io
import json
import math
import re
import struct
import sys
import uuid
from pathlib import Path
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

from PIL import Image

PROFILE = Path(__file__).resolve().parents[1] / "assets/trellis-single-1024-50k.json"
LIMIT = 100 * 1024 * 1024


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def save(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def local_url(value):
    parsed = urlparse(value)
    if (parsed.scheme != "http" or parsed.hostname not in ("127.0.0.1", "localhost", "::1")
            or parsed.username or parsed.password or parsed.query or parsed.fragment
            or parsed.path not in ("", "/")):
        raise ValueError("This local skill requires a loopback HTTP service root URL")
    return value.rstrip("/")


def reference(path):
    data = Path(path).read_bytes()
    if len(data) > 25 * 1024 * 1024:
        raise ValueError("Reference exceeds 25 MiB")
    with Image.open(io.BytesIO(data)) as im:
        if im.format != "PNG" or getattr(im, "is_animated", False):
            raise ValueError("Use one still PNG with transparent background")
        if min(im.size) < 64 or max(im.size) > 4096 or im.width * im.height > 16_777_216:
            raise ValueError("PNG edges must be 64-4096 pixels, at most 16 megapixels")
        if im.getexif().get(274, 1) != 1:
            raise ValueError("Reference has an unapplied EXIF orientation")
        alpha = im.convert("RGBA").getchannel("A")
        if alpha.getextrema()[0] == 255 or alpha.getextrema()[1] == 0:
            raise ValueError("Reference must have non-opaque alpha and visible content")
        dimensions = list(im.size)
    return data, dimensions


class Client:
    def __init__(self, api="http://127.0.0.1:8000", backend=None):
        self.api = local_url(api) if backend is None else None
        self.backend = local_url(backend) if backend else None

    def request(self, base, path, data=None, content_type=None):
        req = Request(base + path, data=data)
        if content_type:
            req.add_header("Content-Type", content_type)
        with urlopen(req, timeout=60) as response:
            result = response.read(LIMIT + 1)
        if len(result) > LIMIT:
            raise ValueError("Service response exceeds the skill's 100 MiB limit")
        return result

    def get(self, path):
        return json.loads(self.request(self.backend, path))

    def post(self, path, value):
        return json.loads(self.request(self.backend, path, json.dumps(value).encode(), "application/json"))

    def idle(self):
        if self.api:
            health = json.loads(self.request(self.api, "/health"))
            if not health.get("backend", {}).get("available") or health["active"] or health["queued"]:
                raise RuntimeError("API/backend unavailable or busy; stop without submitting")
            discovered = local_url(health["backend"]["url"])
            if self.backend is not None and discovered != self.backend:
                raise RuntimeError("Backend changed during preflight; stop")
            self.backend = discovered
        queue = self.get("/queue")
        if queue["queue_running"] or queue["queue_pending"]:
            raise RuntimeError("Shared ComfyUI queue is busy; stop without submitting")

    def preflight(self):
        self.idle()
        graph = read(PROFILE)
        info = self.get("/object_info")
        missing = sorted({node["class_type"] for node in graph.values()} - set(info))
        if missing:
            raise RuntimeError("Missing required nodes: " + ", ".join(missing))
        for node_name, field in (("319", "unet_name"), ("117", "vae_name"),
                                 ("118", "vae_name"), ("15", "clip_name")):
            node = graph[node_name]
            choices = info[node["class_type"]]["input"]["required"][field][0]
            if node["inputs"][field] not in choices:
                raise RuntimeError("Missing existing weight: " + node["inputs"][field])
        self.idle()
        return {"state": "READY", "backend": self.backend, "api": self.api,
                "profile_sha256": sha(PROFILE.read_bytes()), "seed": 42, "resolution": 1024,
                "target_faces": 50000, "generation_ready_only": True}

    def upload(self, data, filename):
        boundary = "skill3d" + uuid.uuid4().hex
        body = (f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{filename}"\r\n'
                'Content-Type: image/png\r\n\r\n').encode() + data + f"\r\n--{boundary}--\r\n".encode()
        result = json.loads(self.request(self.backend, "/upload/image", body,
                                        "multipart/form-data; boundary=" + boundary))
        parts = (result.get("subfolder", "") + "/" + result["name"]).strip("/").replace("\\", "/")
        if any(part in ("..", ".") for part in parts.split("/")) or ":" in parts:
            raise ValueError("Unsafe backend image path")
        return parts


def submit(client, image, output, asset_id):
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", asset_id):
        raise ValueError("asset-id must be 1-64 lowercase letters, digits, underscores or hyphens")
    folder = Path(output).resolve()
    if folder.exists():
        raise RuntimeError("Output already exists: collect/reconcile it; never resubmit or overwrite")
    data, dimensions = reference(image)
    ready = client.preflight()
    folder.mkdir(parents=True, exist_ok=False)
    (folder / "reference.png").write_bytes(data)
    job = {**ready, "state": "PREPARING", "asset_id": asset_id, "client_id": str(uuid.uuid4()),
           "reference_sha256": sha(data), "reference_dimensions": dimensions, "profile": "trellis-single-1024-50k"}
    save(folder / "job.json", job)
    token = job["client_id"].replace("-", "")
    try:
        uploaded = client.upload(data, asset_id + "-" + sha(data)[:16] + "-" + token[:8] + ".png")
        client.idle()
    except Exception as error:
        job.update(state="NOT_SUBMITTED", error=str(error))
        save(folder / "job.json", job)
        raise
    graph = read(PROFILE)
    graph["122"]["inputs"]["image"] = uploaded
    prefix = "skill-3d/" + asset_id + "/" + token
    graph["save"]["inputs"]["filename_prefix"] = prefix + "/model"
    graph["conditioning_image"]["inputs"]["filename_prefix"] = prefix + "/conditioning"
    save(folder / "prompt.json", graph)
    job.update(state="SUBMISSION_INTENT", prompt_sha256=sha((folder / "prompt.json").read_bytes()))
    save(folder / "job.json", job)
    try:
        reply = client.post("/prompt", {"prompt": graph, "client_id": job["client_id"]})
    except Exception as error:
        job.update(state="SUBMISSION_UNKNOWN", error=str(error))
        save(folder / "job.json", job)
        raise RuntimeError("Submission uncertain: reconcile existing queue/history; do not POST again") from error
    save(folder / "submission.json", reply)
    if reply.get("node_errors") or not reply.get("prompt_id"):
        job.update(state="REJECTED_OR_UNKNOWN", response=reply)
        save(folder / "job.json", job)
        raise RuntimeError("Prompt rejected or no ID; stop and inspect submission.json")
    job.update(state="SUBMITTED", prompt_id=reply["prompt_id"])
    save(folder / "job.json", job)
    return {"state": job["state"], "prompt_id": job["prompt_id"], "output": str(folder)}


def inspect_glb(data):
    if len(data) < 28 or struct.unpack_from("<4sII", data) != (b"glTF", 2, len(data)):
        raise ValueError("Invalid GLB header or length")
    chunks, cursor = [], 12
    while cursor < len(data):
        if cursor + 8 > len(data):
            raise ValueError("Truncated GLB chunk header")
        length, kind = struct.unpack_from("<II", data, cursor)
        cursor += 8
        if length % 4 or cursor + length > len(data):
            raise ValueError("Invalid GLB chunk size")
        chunks.append((kind, data[cursor:cursor + length]))
        cursor += length
    if len(chunks) != 2 or [x[0] for x in chunks] != [0x4E4F534A, 0x004E4942]:
        raise ValueError("Expected JSON and embedded BIN chunks")
    doc, binary = json.loads(chunks[0][1]), chunks[1][1]
    if doc.get("asset", {}).get("version") != "2.0" or not doc.get("meshes"):
        raise ValueError("Missing glTF2 mesh")

    def values(index, wanted_type, wanted_components):
        acc = doc["accessors"][index]
        if acc.get("sparse") or acc["type"] != wanted_type or acc["componentType"] not in wanted_components:
            raise ValueError("Unsupported mesh accessor for fixed profile")
        fmt, scalar_bytes = {5126: ("f", 4), 5125: ("I", 4), 5123: ("H", 2), 5121: ("B", 1)}[acc["componentType"]]
        count = {"VEC2": 2, "VEC3": 3, "VEC4": 4, "SCALAR": 1}[wanted_type]
        view = doc["bufferViews"][acc["bufferView"]]
        offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", count * scalar_bytes)
        if view.get("buffer", 0) != 0 or acc["count"] <= 0 or stride < count * scalar_bytes:
            raise ValueError("Invalid accessor buffer/count/stride")
        end = offset + (acc["count"] - 1) * stride + count * scalar_bytes
        if end > view.get("byteOffset", 0) + view["byteLength"] or end > len(binary):
            raise ValueError("Accessor extends beyond buffer")
        return [struct.unpack_from("<" + fmt * count, binary, offset + i * stride) for i in range(acc["count"])]

    total_vertices, total_faces = 0, 0
    attribute_issues = {"zero_normals": 0, "non_unit_normals": 0, "zero_tangents": 0,
                        "non_unit_tangents": 0, "non_orthogonal_tangents": 0,
                        "invalid_tangent_handedness": 0}
    checked_attributes = {"POSITION"}
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            if primitive.get("mode", 4) != 4:
                raise ValueError("Expected triangle mesh")
            pts = values(primitive["attributes"]["POSITION"], "VEC3", (5126,))
            ids = values(primitive["indices"], "SCALAR", (5121, 5123, 5125))
            if len(ids) % 3 or not all(math.isfinite(v) for p in pts for v in p):
                raise ValueError("Non-finite geometry or invalid triangle count")
            if not all(0 <= index[0] < len(pts) for index in ids):
                raise ValueError("Triangle index outside positions")
            attributes = {}
            for semantic, kind in (("NORMAL", "VEC3"), ("TEXCOORD_0", "VEC2"), ("TANGENT", "VEC4")):
                if semantic not in primitive["attributes"]:
                    continue
                rows = values(primitive["attributes"][semantic], kind, (5126,))
                if len(rows) != len(pts) or not all(math.isfinite(v) for row in rows for v in row):
                    raise ValueError("Non-finite or mismatched vertex attribute: " + semantic)
                attributes[semantic] = rows
                checked_attributes.add(semantic)
            for semantic, prefix in (("NORMAL", "normals"), ("TANGENT", "tangents")):
                for row in attributes.get(semantic, []):
                    length = math.sqrt(sum(v * v for v in row[:3]))
                    attribute_issues["zero_" + prefix] += length <= 1e-6
                    attribute_issues["non_unit_" + prefix] += abs(length - 1.0) > 1e-3
            for normal, tangent in zip(attributes.get("NORMAL", []), attributes.get("TANGENT", [])):
                attribute_issues["non_orthogonal_tangents"] += abs(sum(normal[i] * tangent[i] for i in range(3))) > 1e-3
            attribute_issues["invalid_tangent_handedness"] += sum(abs(abs(row[3]) - 1.0) > 1e-3 for row in attributes.get("TANGENT", []))
            total_vertices += len(pts)
            total_faces += len(ids) // 3
    if not total_faces or len(doc.get("images", [])) < 1 or not doc.get("materials"):
        raise ValueError("Expected non-empty textured candidate")
    for entry in doc["images"]:
        view = doc["bufferViews"][entry["bufferView"]]
        offset, length = view.get("byteOffset", 0), view["byteLength"]
        if offset + length > len(binary):
            raise ValueError("Embedded image extends beyond BIN")
        with Image.open(io.BytesIO(binary[offset:offset + length])) as im:
            im.verify()
    return {"vertices": total_vertices, "triangles": total_faces, "embedded_images": len(doc["images"]),
            "finite_positions": True, "finite_vertex_attributes": True,
            "checked_attributes": sorted(checked_attributes), "attribute_issues": attribute_issues,
            "container_valid": True, "geometry_straightness_checked": False, "topology_checked": False}


def status(folder):
    folder = Path(folder).resolve()
    job = read(folder / "job.json")
    if not job.get("prompt_id"):
        raise RuntimeError("No saved prompt ID; stop and reconcile intent, never resubmit automatically")
    if sha((folder / "reference.png").read_bytes()) != job["reference_sha256"] or sha((folder / "prompt.json").read_bytes()) != job["prompt_sha256"]:
        raise ValueError("Saved input/graph hash changed; stop")
    client = Client(backend=job["backend"])
    history = client.get("/history/" + job["prompt_id"])
    if job["prompt_id"] not in history:
        queue = client.get("/queue")
        active = any(item[1] == job["prompt_id"] for item in queue["queue_running"])
        pending = any(item[1] == job["prompt_id"] for item in queue["queue_pending"])
        return client, job, None, {"state": "RUNNING" if active else "QUEUED" if pending else "UNKNOWN", "prompt_id": job["prompt_id"]}
    record = history[job["prompt_id"]]
    executed = record.get("prompt", [])
    if (len(executed) < 4 or executed[2] != read(folder / "prompt.json")
            or executed[3].get("client_id") != job["client_id"]):
        raise ValueError("History graph/client does not match this saved job; stop")
    save(folder / "history.json", record)
    state = record["status"]
    if state.get("status_str") != "success":
        raise RuntimeError("Backend failed; inspect saved history.json and stop")
    if not state.get("completed"):
        return client, job, None, {"state": "RUNNING", "prompt_id": job["prompt_id"]}
    return client, job, record, {"state": "COMPLETED_NEEDS_COLLECTION", "prompt_id": job["prompt_id"]}


def write_same_or_new(path, data):
    if path.exists() and path.read_bytes() != data:
        raise ValueError("Existing artifact differs; preserve it and stop: " + path.name)
    if not path.exists():
        path.write_bytes(data)


def reconcile(folder, prompt_id):
    folder = Path(folder).resolve()
    job = read(folder / "job.json")
    if job.get("prompt_id") and job["prompt_id"] != prompt_id:
        raise ValueError("Existing prompt ID differs; stop")
    if not re.fullmatch(r"[0-9a-f-]{36}", prompt_id):
        raise ValueError("Expected an explicit ComfyUI prompt UUID")
    graph = read(folder / "prompt.json")
    if sha((folder / "prompt.json").read_bytes()) != job["prompt_sha256"]:
        raise ValueError("Saved graph changed; stop")
    client = Client(backend=job["backend"])
    history = client.get("/history/" + prompt_id)
    if prompt_id in history:
        item = history[prompt_id]["prompt"]
    else:
        queue = client.get("/queue")
        found = [item for item in queue["queue_running"] + queue["queue_pending"] if item[1] == prompt_id]
        if len(found) != 1:
            raise RuntimeError("No matching existing prompt; retain UNKNOWN and do not resubmit")
        item = found[0]
    if item[2] != graph or item[3].get("client_id") != job["client_id"]:
        raise ValueError("Existing graph/client ID does not match this intent; stop")
    job.update(prompt_id=prompt_id, state="SUBMITTED")
    save(folder / "job.json", job)
    return {"state": "RECONCILED_EXISTING_PROMPT", "prompt_id": prompt_id}


def collect(folder):
    folder = Path(folder).resolve()
    client, job, record, progress = status(folder)
    if record is None:
        return progress
    output = record["outputs"].get("save", {})
    entries = [entry for group in output.values() if isinstance(group, list) for entry in group
               if isinstance(entry, dict) and str(entry.get("filename", "")).endswith(".glb")]
    images = record["outputs"].get("conditioning_image", {}).get("images", [])
    if len(entries) != 1 or len(images) != 1:
        raise ValueError("GLB or actual conditioning missing/ambiguous; stop")
    for entry in (entries[0], images[0]):
        if entry.get("type") != "output":
            raise ValueError("Expected generated output files")
    glb = client.request(client.backend, "/view?" + urlencode(entries[0]))
    stats = inspect_glb(glb)
    png = client.request(client.backend, "/view?" + urlencode(images[0]))
    with Image.open(io.BytesIO(png)) as im:
        if im.format != "PNG" or im.size != (1024, 1024):
            raise ValueError("Unexpected conditioning format/size")
        im.verify()
    write_same_or_new(folder / "raw.glb", glb)
    write_same_or_new(folder / "conditioning.png", png)
    result = {"state": "ART_REVIEW_REQUIRED", "prompt_id": job["prompt_id"], "glb_sha256": sha(glb),
              "conditioning_sha256": sha(png), "backend_files": {"glb": entries[0], "conditioning": images[0]},
              "technical_checks": stats, "art_review_passed": False}
    save(folder / "result.json", result)
    job["state"] = result["state"]
    save(folder / "job.json", job)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    for name in ("preflight", "submit"):
        command = commands.add_parser(name)
        command.add_argument("--url", default="http://127.0.0.1:8000")
        command.add_argument("--backend")
        if name == "submit":
            command.add_argument("--image", required=True)
            command.add_argument("--output", required=True)
            command.add_argument("--asset-id", required=True)
    for name in ("status", "collect"):
        commands.add_parser(name).add_argument("--output", required=True)
    recover = commands.add_parser("reconcile")
    recover.add_argument("--output", required=True)
    recover.add_argument("--prompt-id", required=True)
    commands.add_parser("inspect").add_argument("--glb", required=True)
    args = parser.parse_args()
    try:
        if args.action == "preflight":
            result = Client(args.url, args.backend).preflight()
        elif args.action == "submit":
            result = submit(Client(args.url, args.backend), args.image, args.output, args.asset_id)
        elif args.action == "collect":
            result = collect(args.output)
        elif args.action == "status":
            result = status(args.output)[3]
        elif args.action == "reconcile":
            result = reconcile(args.output, args.prompt_id)
        else:
            result = inspect_glb(Path(args.glb).read_bytes())
        print(json.dumps(result, ensure_ascii=False))
        return 2 if result.get("state") == "UNKNOWN" else 0
    except Exception as error:
        print(json.dumps({"state": "STOPPED", "error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())
