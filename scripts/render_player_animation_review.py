"""Render the saved v021 Actions without changing the .blend file."""
import bpy
import sys
from pathlib import Path
from mathutils import Vector

root = Path(__file__).resolve().parents[1]
out = root / 'docs/validation/player-animations-v021'
wrist_review = '--wrists-only' in sys.argv
finger_review = '--relaxed-fingers' in sys.argv
jump_review = '--jump' in sys.argv
climb_review = '--climb' in sys.argv
hand_review = '--hands' in sys.argv or wrist_review or finger_review
if hand_review: out /= 'relaxed-fingers' if finger_review else ('wrist-only' if wrist_review else 'hands')
if jump_review: out /= 'jump'
if climb_review: out /= 'climb'
out.mkdir(parents=True, exist_ok=True)
rig = bpy.data.objects['PLAYER_Rig']
scene = bpy.data.scenes.new('Animation_Review_Render')
scene.collection.children.link(bpy.data.collections['PLAYER_GAME'])
bpy.context.window.scene = scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.render.resolution_x = 700
scene.render.resolution_y = 850
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world = bpy.data.worlds.new('Animation_Review_World')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.12, .14, .17, 1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .6
camera_data = bpy.data.cameras.new('Animation_Review_Camera')
camera = bpy.data.objects.new('Animation_Review_Camera', camera_data)
scene.collection.objects.link(camera)
camera.location = (2.5, -4, 1.8)
camera.rotation_euler = (Vector((0, 0, .8)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera_data.type = 'ORTHO'
camera_data.ortho_scale = 1.9
scene.camera = camera
for name, position, energy, size in [('Key', (2, -3, 4), 600, 4), ('Fill', (-3, -1, 2), 350, 3)]:
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = energy
    data.shape = 'DISK'
    data.size = size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (Vector((0, 0, .8)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
review_frames = [('jump_rise', 12), ('jump_fall', 12), ('jump_land', 6)] if jump_review else [('idle', 0), ('jog_forward', 8), ('run_forward', 8)]
if climb_review: review_frames = [('climb_hold', 0), ('climb_up', 0), ('climb_up', 12), ('climb_left', 8), ('climb_exit', 9)]
for clip, frame in review_frames:
    action = bpy.data.actions['PLAYER_' + clip]
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    scene.frame_set(frame)
    suffix = '_' + str(frame) if climb_review else ''
    scene.render.filepath = str(out / ('blender_' + clip + suffix + '.png'))
    bpy.ops.render.render(write_still=True)
    if jump_review or climb_review:
        camera.location = (4, -.5, 1.4)
        camera.rotation_euler = (Vector((0, 0, .8)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(out / ('blender_' + clip + suffix + '_side.png'))
        bpy.ops.render.render(write_still=True)
        camera.location = (2.5, -4, 1.8)
        camera.rotation_euler = (Vector((0, 0, .8)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    if hand_review:
        camera.location = (1, -3, 1.2)
        target = Vector((0, -.06, .8)) if clip == 'idle' else Vector((-.08, -.15, 1.0))
        camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()
        camera_data.ortho_scale = .95 if clip == 'idle' else 1.5
        scene.render.filepath = str(out / ('blender_' + clip + '_hands.png'))
        bpy.ops.render.render(write_still=True)
        camera.location = (2.5, -4, 1.8)
        camera.rotation_euler = (Vector((0, 0, .8)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
        camera_data.ortho_scale = 1.9
print('PLAYER_ANIMATION_REVIEW_RENDERED', flush=True)
