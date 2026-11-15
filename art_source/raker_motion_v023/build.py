"""Raker v023 build: mouth rebuild + grab clips + export.

    blender --background art_source/raker_motion_v022/raker_motion_v022.blend \
        --python art_source/raker_motion_v023/build.py [-- --no-install]

Writes raker_motion_v023.blend next to this file, the export and reports under
.godot/raker-motion-v023/, and (unless --no-install) assets/models/raker/raker.glb.
"""
import json
import struct
import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
WORK = ROOT / '.godot' / 'raker-motion-v023'
sys.path.insert(0, str(HERE))
import author_grab  # noqa: E402
import build_mouth  # noqa: E402

CROUCH_CLEARANCE = 1.85   # enemies/raker.gd CROUCH_HEIGHT, in world metres
MODEL_SCALE = 1.2         # enemies/raker.tscn BodyMesh/Model
IMAGE_NAMES = {'Raker011_Albedo': 'raker_albedo_2k', 'Raker021_HandAlbedo': 'hand_albedo'}


def geometry(scene, rig, mesh, names, baseline=None):
    """Lowest sole and highest point per clip. With a baseline (the v022 clips
    measured the same way) a crouched clip may match its source height but not
    grow past the crouch clearance."""
    report = {}
    for track in rig.animation_data.nla_tracks:
        if track.name not in names:
            continue
        action = track.strips[0].action
        rig.animation_data.action = action
        rig.animation_data.action_slot = action.slots[0]
        low, high = 100.0, -100.0
        for f in range(int(action.frame_range[1]) + 1):
            scene.frame_set(f)
            bpy.context.view_layer.update()
            evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
            me = evaluated.to_mesh()
            zs = [v.co.z for v in me.vertices]
            low = min(low, min(zs))
            high = max(high, max(zs))
            evaluated.to_mesh_clear()
        report[track.name] = {'min_sole_z': round(low, 5), 'max_head_z': round(high, 5)}
        if baseline is None:
            continue
        before = baseline[track.name]
        report[track.name]['v022_max_head_z'] = before['max_head_z']
        assert low > min(-0.004, before['min_sole_z'] - 0.002), (track.name, 'foot below ground', low)
        if '_low_' in track.name or '_seat_' in track.name:
            # Seat clips already raise their elbows above the capsule; the
            # runtime re-solves those arms, so allow them a little travel.
            limit = max(CROUCH_CLEARANCE / MODEL_SCALE, before['max_head_z'] + 0.04)
            assert high < limit, (track.name, 'crouch clearance', high, limit)
    rig.animation_data.action = None
    return report


def export(scene, rig, mesh, path):
    rig.animation_data.action = None
    for track in rig.animation_data.nla_tracks:
        track.mute = False
    for obj in scene.objects:
        obj.select_set(False)
    rig.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    names = rig.name, mesh.name
    rig.name, mesh.name = 'Raker_Rig', 'Raker_Mesh'
    try:
        bpy.ops.export_scene.gltf(filepath=str(path), use_selection=True, use_active_scene=True,
                                  export_animations=True, export_animation_mode='NLA_TRACKS', export_def_bones=True,
                                  export_force_sampling=True, export_skins=True, export_yup=True,
                                  export_vertex_color='NONE')
    finally:
        rig.name, mesh.name = names
        for track in rig.animation_data.nla_tracks:
            track.mute = True


def install(source, target, previous):
    """Keep the names Godot derives its extracted texture files from."""
    data = source.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    binary = data[20 + length:]
    for image in gltf['images']:
        image['name'] = IMAGE_NAMES.get(image['name'], image['name'])
    old = previous.read_bytes()
    old = json.loads(old[20:20 + struct.unpack_from('<I', old, 12)[0]])
    assert {a['name'] for a in gltf['animations']} == {a['name'] for a in old['animations']}, 'animation set changed'
    assert [n['name'] for n in gltf['nodes'] if 'mesh' in n] == ['Raker_Mesh']
    assert sorted(old['nodes'][j]['name'] for j in old['skins'][0]['joints']) == sorted(gltf['nodes'][j]['name'] for j in gltf['skins'][0]['joints']), 'skeleton changed'
    assert [m['name'] for m in gltf['materials']] == [m['name'] for m in old['materials']], 'material order changed'
    encoded = json.dumps(gltf, separators=(',', ':')).encode()
    encoded += b' ' * ((-len(encoded)) % 4)
    target.write_bytes(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(encoded) + len(binary))
                       + struct.pack('<II', len(encoded), 0x4E4F534A) + encoded + binary)
    return {'bytes': target.stat().st_size, 'images': [i['name'] for i in gltf['images']],
            'animations': len(gltf['animations'])}


def main():
    arguments = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    WORK.mkdir(parents=True, exist_ok=True)
    report = {'mouth': {}, 'clips': {}}
    build_mouth.build(report['mouth'])
    scene = bpy.data.scenes['RAKER_MOTION_V022']
    scene.name = 'RAKER_MOTION_V023'
    rig = bpy.data.objects[build_mouth.RIG]
    mesh = bpy.data.objects[build_mouth.MESH]
    rig.name, mesh.name = 'Motion023_Rig', 'Motion023_Mesh'
    bpy.context.window.scene = scene
    scene.render.fps = author_grab.FPS
    grab_clips = {t.name for t in rig.animation_data.nla_tracks if t.name.startswith('grab_')}
    before = geometry(scene, rig, mesh, grab_clips)
    author_grab.author(scene, rig, report['clips'])
    try:
        report['geometry'] = geometry(scene, rig, mesh, grab_clips, before)
    except AssertionError:
        print('BASELINE', json.dumps(before))
        raise
    authored = WORK / 'authored.glb'
    export(scene, rig, mesh, authored)
    idle = next(t.strips[0].action for t in rig.animation_data.nla_tracks if t.name == 'idle')
    rig.animation_data.action = idle
    rig.animation_data.action_slot = idle.slots[0]
    scene.frame_start, scene.frame_end = 0, int(idle.frame_range[1])
    scene.frame_set(0)
    bpy.data.libraries.write(str(HERE / 'raker_motion_v023.blend'), {scene}, fake_user=True, compress=True)
    if '--no-install' not in arguments:
        target = ROOT / 'assets' / 'models' / 'raker' / 'raker.glb'
        baseline = WORK / 'previous.glb'
        if not baseline.exists():
            baseline.write_bytes(target.read_bytes())
        report['install'] = install(authored, target, baseline)
    (WORK / 'build-report.json').write_text(json.dumps(report, indent=2))
    print('BUILD', json.dumps({k: v for k, v in report.items() if k != 'clips'}))


main()
