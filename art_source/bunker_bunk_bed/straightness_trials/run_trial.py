"""Submit/collect preserved bed-only experiments, without overwriting candidates."""
import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'scripts'))
from generate_request_model import request_json

BASE = Path(__file__).resolve().parent
API = 'http://127.0.0.1:8000'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('case')
    parser.add_argument('--image')
    parser.add_argument('--preset', default='standard1024')
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--collect', action='store_true')
    args = parser.parse_args()
    if not args.case.replace('_', '').isalnum():
        parser.error('Invalid case')
    folder = BASE / args.case
    metadata_path = folder / 'generation.json'
    if args.collect:
        metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
        status = request_json(f"{API}/jobs/{metadata['job_id']}")
        metadata['status'] = status
        if status['state'] == 'succeeded':
            result = request_json(f"{API}/jobs/{metadata['job_id']}/result")
            with urllib.request.urlopen(API + result['download_url'], timeout=30) as response:
                raw = response.read()
            digest = hashlib.sha256(raw).hexdigest()
            if digest != result['validation']['sha256']:
                raise RuntimeError('GLB checksum mismatch')
            (folder / 'raw.glb').write_bytes(raw)
            metadata['result'] = result
        metadata_path.write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
        print(json.dumps({'case': args.case, 'state': status['state'], 'elapsed_seconds': status.get('elapsed_seconds')}))
        return
    image = Path(args.image).resolve()
    raw = image.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    key = f"bed-straightness-{args.case}-{args.preset}-{args.seed}-{digest[:16]}"
    if metadata_path.exists():
        previous = json.loads(metadata_path.read_text(encoding='utf-8'))
        if previous['idempotency_key'] != key:
            raise RuntimeError('Preserve existing case; use another name')
    boundary = 'bed-' + digest[:24]
    data = bytearray()
    for field, value in [('asset_id', 'bed_' + args.case), ('preset', args.preset), ('seed', str(args.seed))]:
        data.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"\r\n\r\n{value}\r\n'.encode())
    data.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="reference.png"\r\nContent-Type: image/png\r\n\r\n'.encode())
    data.extend(raw)
    data.extend(f'\r\n--{boundary}--\r\n'.encode())
    job = request_json(API + '/jobs', bytes(data), {'Content-Type': 'multipart/form-data; boundary=' + boundary, 'Idempotency-Key': key})
    folder.mkdir(parents=True, exist_ok=True)
    metadata = {'api': API, 'case': args.case, 'reference': str(image.relative_to(ROOT)).replace('\\', '/'), 'reference_sha256': digest, 'preset': args.preset, 'seed': args.seed, 'idempotency_key': key, **job}
    metadata_path.write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(metadata))


if __name__ == '__main__':
    main()
