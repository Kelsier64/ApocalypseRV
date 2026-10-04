"""Controlled ComfyUI variants. Preserve prompt/history and unchanged raw outputs.

`frame` runs native crop/composite/stitch nodes to produce three equal square
input panels at shared scale. This only prepares camera framing, not bed art.
`submit` bypasses each per-view CropToMask, retaining exactly the same canvas.
"""
import argparse
import hashlib
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from PIL import Image

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'scripts'))
from generate_request_model import request_json
COMFY = 'http://127.0.0.1:8188'
WORKFLOWS = Path('C:/Users/evan4/Apps/Pixal3D-API/workflows')


def upload(path):
    raw = path.read_bytes()
    boundary = 'bed-' + hashlib.sha256(raw).hexdigest()[:24]
    data = f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{path.name}"\r\nContent-Type: image/png\r\n\r\n'.encode() + raw
    data += f'\r\n--{boundary}--\r\n'.encode()
    result = request_json(COMFY + '/upload/image', data, {'Content-Type': 'multipart/form-data; boundary=' + boundary})
    return (result.get('subfolder', '') + '/' + result['name']).lstrip('/')


def submit(case, graph):
    queue = request_json(COMFY + '/queue')
    if queue['queue_running'] or queue['queue_pending']:
        raise RuntimeError('Wait until the shared generation queue is idle')
    folder = BASE / case
    if (folder / 'prompt.json').exists():
        raise RuntimeError('Case already exists; collect it rather than duplicate')
    result = request_json(COMFY + '/prompt', json.dumps({'prompt': graph}).encode(), {'Content-Type': 'application/json'})
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'prompt.json').write_text(json.dumps(graph, indent=2) + '\n', encoding='utf-8')
    (folder / 'generation.json').write_text(json.dumps({'case': case, 'backend': COMFY, **result}, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))


def collect(case):
    folder = BASE / case
    metadata = json.loads((folder / 'generation.json').read_text(encoding='utf-8'))
    history = request_json(COMFY + '/history/' + metadata['prompt_id'])
    if not history:
        print(json.dumps({'case': case, 'state': 'running_or_queued'}))
        return
    record = history[metadata['prompt_id']]
    (folder / 'history.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    status = record['status']
    for output in record['outputs'].values():
        for key, files in output.items():
            if not isinstance(files, list):
                continue
            for item in files:
                if not isinstance(item, dict) or 'filename' not in item:
                    continue
                suffix = Path(item['filename']).suffix
                if suffix not in ('.glb', '.png'):
                    continue
                url = COMFY + '/view?' + urllib.parse.urlencode(item)
                with urllib.request.urlopen(url, timeout=30) as response:
                    raw = response.read()
                filename = 'framed_reference.png' if case.startswith('framed') else Path(item['filename']).name
                destination = folder / ('raw.glb' if suffix == '.glb' else filename)
                destination.write_bytes(raw)
                metadata['output_sha256'] = hashlib.sha256(raw).hexdigest()
    metadata['status'] = status
    (folder / 'generation.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'case': case, 'status': status}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['frame', 'submit', 'preprocess', 'collect'])
    parser.add_argument('case')
    parser.add_argument('--image')
    parser.add_argument('--preset', choices=['preview512', 'standard1024', 'threeview512', 'threeview1024'], default='threeview1024')
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--fov', type=float, default=20)
    args = parser.parse_args()
    if not args.case.replace('_', '').isalnum():
        parser.error('Invalid case')
    if args.action == 'collect':
        collect(args.case)
        return
    path = Path(args.image).resolve()
    width, height = Image.open(path).size
    image = upload(path)
    if args.action == 'frame':
        # Equal 724px square cameras; common scale, center height and margins.
        # Generated art did not honor equal-cell layout. Shift only crop centers.
        graph = {
            'input': {'class_type': 'LoadImage', 'inputs': {'image': image}},
            'black': {'class_type': 'EmptyImage', 'inputs': {'width': width, 'height': height, 'batch_size': 1, 'color': 0}},
            'alpha': {'class_type': 'InvertMask', 'inputs': {'mask': ['input', 1]}},
            'composite': {'class_type': 'ImageCompositeMasked', 'inputs': {'destination': ['black', 0], 'source': ['input', 0], 'mask': ['alpha', 0], 'x': 0, 'y': 0, 'resize_source': False}},
        }
        for view, x in [('front', 60), ('back', 1387)]:
            graph[view] = {'class_type': 'ImageCrop', 'inputs': {'image': ['composite', 0], 'width': 724, 'height': 724, 'x': x, 'y': 0}}
        # Isolate the narrow end so the square canvas does not capture an
        # adjacent view's post. Paste at the same pixel scale; no resize.
        graph['left_isolate'] = {'class_type': 'ImageCrop', 'inputs': {'image': ['composite', 0], 'width': 550, 'height': 724, 'x': 810, 'y': 0}}
        graph['square_black'] = {'class_type': 'EmptyImage', 'inputs': {'width': 724, 'height': 724, 'batch_size': 1, 'color': 0}}
        graph['left'] = {'class_type': 'ImageCompositeMasked', 'inputs': {'destination': ['square_black', 0], 'source': ['left_isolate', 0], 'x': 87, 'y': 0, 'resize_source': False}}
        for name, left, right in [('pair', 'front', 'left'), ('sheet', 'pair', 'back')]:
            graph[name] = {'class_type': 'ImageStitch', 'inputs': {'image1': [left, 0], 'image2': [right, 0], 'direction': 'right', 'match_image_size': False, 'spacing_width': 0, 'spacing_color': 'black'}}
        graph['save'] = {'class_type': 'SaveImage', 'inputs': {'images': ['sheet', 0], 'filename_prefix': 'bed_straightness/' + args.case}}
    else:
        graph = json.loads((WORKFLOWS / (args.preset + '.json')).read_text(encoding='utf-8'))
        graph['122']['inputs']['image'] = image
        if args.action == 'preprocess':
            if args.preset.startswith('threeview'):
                names = ['front', 'left', 'back']
                nodes = ['122', '193']
                for index, view in enumerate(names):
                    graph[view + '_crop']['inputs'].update(width=height, height=height, x=index * height, y=0)
                    nodes += [view + '_crop', view + '_mask', view + '_frame']
                graph = {key: graph[key] for key in nodes}
                for view in names:
                    graph['save_' + view] = {'class_type': 'SaveImage', 'inputs': {'images': [view + '_frame', 0], 'filename_prefix': 'bed_straightness/' + args.case + '/' + view}}
            else:
                nodes = ['122', '193', '312', '55', '56', '242']
                # Discover dependencies instead of assuming the mask node id.
                needed = set(nodes)
                pending = list(nodes)
                while pending:
                    for value in graph[pending.pop()]['inputs'].values():
                        if isinstance(value, list) and len(value) == 2 and value[0] in graph and value[0] not in needed:
                            needed.add(value[0])
                            pending.append(value[0])
                graph = {key: graph[key] for key in needed}
                graph['preview'] = {'class_type': 'PreviewAny', 'inputs': {'source': ['242', 0]}}
            submit(args.case, graph)
            return
        if args.preset.startswith('threeview'):
            if width != height * 3:
                raise RuntimeError('Need three equal square panels')
            for index, view in enumerate(['front', 'left', 'back']):
                graph[view + '_crop']['inputs'].update(width=height, height=height, x=index * height, y=0)
                # Preprocessed black canvas: do not independently zoom each view.
                graph['298']['inputs'][view] = [view + '_crop', 0]
            graph['298']['inputs']['fov'] = args.fov
        else:
            graph['298']['inputs']['camera_angle_x'] = args.fov
        for node in graph.values():
            if node['class_type'] == 'KSampler':
                node['inputs']['seed'] = args.seed
        graph['save']['inputs']['filename_prefix'] = 'bed_straightness/' + args.case
    submit(args.case, graph)


if __name__ == '__main__':
    main()
