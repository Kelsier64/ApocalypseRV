"""Reproducible live bed check; only submit explicitly, never resubmit on collect."""
import argparse
import hashlib
import io
import json
from pathlib import Path

import requests
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('action', choices=['submit', 'collect', 'invalid'])
parser.add_argument('--url', default='http://127.0.0.1:8001')
parser.add_argument('--case', required=True, type=Path)
parser.add_argument('--image', type=Path)
parser.add_argument('--preset', default='threeview512')
parser.add_argument('--separate', action='store_true')
parser.add_argument('--background', default='auto')
parser.add_argument('--fov', type=float)
parser.add_argument('--seed', type=int, default=42)
args = parser.parse_args()
args.case.mkdir(parents=True, exist_ok=True)

def save(name, data):
    (args.case / name).write_text(json.dumps(data, indent=2), encoding='utf-8')

if args.action == 'invalid':
    stream = io.BytesIO()
    Image.new('RGB', (2171, 724)).save(stream, 'PNG')
    before = requests.get(args.url + '/health', timeout=10).json()
    response = requests.post(args.url + '/jobs', files={'image': ('bad.png', stream.getvalue(), 'image/png')},
                             data={'asset_id': 'bunker_bunk_bed', 'preset': 'threeview512'}, timeout=15)
    after = requests.get(args.url + '/health', timeout=10).json()
    assert response.status_code == 422, response.text
    assert (before['active'], before['queued']) == (after['active'], after['queued'])
    save('invalid_sheet.json', {'status_code': response.status_code, 'response': response.json(), 'queue_unchanged': True})
    print('Invalid panel ratio rejected before queueing')
elif args.action == 'submit':
    if not args.image:
        parser.error('--image is required for submit')
    endpoint = '/jobs'
    if args.separate:
        with Image.open(args.image) as sheet:
            assert sheet.width == sheet.height * 3
            files = {}
            for index, view in enumerate(('front', 'left', 'back')):
                stream = io.BytesIO()
                sheet.crop((index * sheet.height, 0, (index + 1) * sheet.height, sheet.height)).save(stream, 'PNG')
                files[view] = (view + '.png', stream.getvalue(), 'image/png')
        endpoint = '/jobs/multiview'
    else:
        files = {'image': (args.image.name, args.image.read_bytes(), 'image/png')}
    options = {'asset_id': 'bunker_bunk_bed', 'preset': args.preset, 'seed': str(args.seed), 'background': args.background}
    if args.fov is not None:
        options['fov'] = str(args.fov)
    key = 'v2-bed-smoke-' + args.case.name
    response = requests.post(args.url + endpoint, files=files, data=options, headers={'Idempotency-Key': key}, timeout=30)
    response.raise_for_status()
    submitted = response.json()
    save('api_response.json', submitted)
    save('request.json', {'endpoint': endpoint, 'image': str(args.image.resolve()), 'options': options, 'idempotency_key': key})
    duplicate = requests.post(args.url + endpoint, files=files, data=options, headers={'Idempotency-Key': key}, timeout=30)
    duplicate.raise_for_status()
    assert duplicate.json()['job_id'] == submitted['job_id']
    save('idempotency.json', {'same_job_id': True, 'duplicate': duplicate.json()})
    print(json.dumps(submitted))
else:
    submitted = json.loads((args.case / 'api_response.json').read_text(encoding='utf-8'))
    job_id = submitted['job_id']
    response = requests.get(args.url + '/jobs/' + job_id, timeout=15)
    response.raise_for_status()
    job = response.json()
    save('job.json', job)
    print(json.dumps({key: job.get(key) for key in ('job_id', 'state', 'prompt_id', 'error', 'elapsed_seconds')}))
    if job['state'] == 'failed':
        raise SystemExit(1)
    if job['state'] == 'succeeded':
        result = requests.get(args.url + '/jobs/' + job_id + '/result', timeout=15)
        result.raise_for_status()
        result = result.json()
        save('result.json', result)
        glb = requests.get(args.url + '/jobs/' + job_id + '/result.glb', timeout=90)
        glb.raise_for_status()
        data = glb.content
        actual = hashlib.sha256(data).hexdigest()
        assert actual == result['validation']['sha256']
        (args.case / 'raw.glb').write_bytes(data)
        inputs = requests.get(args.url + '/jobs/' + job_id + '/inputs', timeout=15)
        inputs.raise_for_status()
        save('inputs.json', inputs.json())
        conditioning = {}
        for view, url in result['conditioning'].items():
            image_response = requests.get(args.url + url, timeout=30)
            image_response.raise_for_status()
            (args.case / ('conditioning_' + view + '.png')).write_bytes(image_response.content)
            with Image.open(io.BytesIO(image_response.content)) as image:
                conditioning[view] = {'size': list(image.size), 'rgb_bounds': image.convert('RGB').getbbox(),
                                      'sha256': hashlib.sha256(image_response.content).hexdigest()}
        assert set(conditioning) == set(job['input_views'])
        if job['inputs']['mode'] == 'multiview':
            assert all(item['size'] == [1024, 1024] for item in conditioning.values())
        save('download_validation.json', {'glb_sha256': actual, 'conditioning': conditioning})
        print('Downloaded GLB and all actual conditioning PNGs; SHA256 matches')
