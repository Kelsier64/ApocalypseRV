"""Submit/resume one modeling reference using the local Pixal3D API.

Usage: python scripts/generate_request_model.py oil-barrel --image reference.png
Use --collect after completion to download the unchanged output into art_source.
Generation metadata is kept beside each asset, never in a shared job manifest.
"""
import argparse
import hashlib
import json
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def request_json(url, data=None, headers=None):
    request = urllib.request.Request(url, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"HTTP {error.code}: {error.read().decode()}") from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("request", help="Folder in docs/modeling/requests")
    parser.add_argument("--image", help="Reference filename inside the request folder")
    parser.add_argument("--part", default="", help="Independent moving part, e.g. body/lid")
    parser.add_argument("--preset", choices=["preview512", "standard1024", "threeview512", "threeview1024"], default="standard1024")
    parser.add_argument("--variant", default="", help="Storage namespace, e.g. threeview; identical inputs still reuse the API job")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--api", default="http://127.0.0.1:8000")
    parser.add_argument("--idempotency-key", help="Resume a key used for an earlier manual submission")
    parser.add_argument("--collect", action="store_true")
    args = parser.parse_args()
    request_dir = ROOT / "docs/modeling/requests" / args.request
    if request_dir.parent != ROOT / "docs/modeling/requests" or not request_dir.is_dir():
        parser.error("Unknown request folder")
    asset_name = args.request.replace("-", "_")
    if any(value and not value.replace("_", "").isalnum() for value in [args.part, args.variant]):
        parser.error("Part/variant must contain only letters, digits or underscores")
    asset_id = asset_name + ("_" + args.part if args.part else "")
    source_dir = ROOT / "art_source" / asset_name
    if args.variant:
        source_dir /= args.variant
    metadata_path = source_dir / ("generation" + ("_" + args.part if args.part else "") + ".json")
    if args.collect:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        status = request_json(f"{args.api}/jobs/{metadata['job_id']}")
        metadata["status"] = status
        if status["state"] == "succeeded":
            result = request_json(f"{args.api}/jobs/{metadata['job_id']}/result")
            with urllib.request.urlopen(args.api + result["download_url"], timeout=30) as response:
                raw = response.read()
            if hashlib.sha256(raw).hexdigest() != result["validation"]["sha256"]:
                raise RuntimeError("Downloaded GLB checksum mismatch")
            (source_dir / (asset_id + "_raw.glb")).write_bytes(raw)
            metadata["result"] = result
        metadata_path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(json.dumps({"asset_id": asset_id, "job_id": metadata["job_id"], "state": status["state"]}))
        return
    if not args.image:
        parser.error("--image is required for submission")
    image_path = request_dir / args.image
    if image_path.parent != request_dir or not image_path.is_file():
        parser.error("Image must be a file inside the request folder")
    raw = image_path.read_bytes()
    if args.preset.startswith("threeview"):
        from PIL import Image
        with Image.open(image_path) as image:
            width, height = image.size
        if width < 3 or height < 1 or abs(width / height - 3) > 0.06:
            parser.error("Threeview input must be a horizontal 3:1 front/left/back sheet; review equal-width panel contents before submission")
    image_hash = hashlib.sha256(raw).hexdigest()
    key = args.idempotency_key or f"apocalypse-rv-{asset_id}-{args.preset}-seed{args.seed}-{image_hash[:16]}"
    boundary = "pixal3d-" + image_hash[:24]
    data = bytearray()
    for field, value in [("asset_id", asset_id), ("preset", args.preset), ("seed", str(args.seed))]:
        data.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"\r\n\r\n{value}\r\n'.encode())
    data.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="reference.png"\r\nContent-Type: image/png\r\n\r\n'.encode())
    data.extend(raw)
    data.extend(f"\r\n--{boundary}--\r\n".encode())
    previous = {}
    if metadata_path.exists():
        previous = json.loads(metadata_path.read_text(encoding="utf-8"))
        if previous["idempotency_key"] != key:
            raise RuntimeError("Existing generation uses different input/options; preserve it before submitting a variant")
    job = request_json(args.api + "/jobs", bytes(data), {
        "Content-Type": "multipart/form-data; boundary=" + boundary,
        "Idempotency-Key": key,
    })
    source_dir.mkdir(parents=True, exist_ok=True)
    (source_dir / ".gdignore").touch()
    metadata = {
        **previous,
        "api": args.api, "request": str((request_dir / (args.request + ".md")).relative_to(ROOT)).replace("\\", "/"),
        "reference": str(image_path.relative_to(ROOT)).replace("\\", "/"),
        "reference_sha256": image_hash, "asset_id": asset_id, "preset": args.preset,
        "variant": args.variant,
        "seed": args.seed, "idempotency_key": key, "job_id": job["job_id"],
        "submitted_result": job,
    }
    metadata_path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"asset_id": asset_id, **job}))


if __name__ == "__main__":
    main()
