"""Set a clear, saved source-review viewport without touching other Blender windows."""
import bpy
from mathutils import Vector
from pathlib import Path
s=bpy.data.scenes['MONSTER_REFINED_V020'];bpy.context.window.scene=s
r=bpy.data.objects['Refined020_Rig'];m=bpy.data.objects['Refined020_Mesh']
for t in r.animation_data.nla_tracks:t.mute=True
r.animation_data.action=next(t.strips[0].action for t in r.animation_data.nla_tracks if t.name=='idle')
r.animation_data.action_slot=r.animation_data.action.slots[0];s.frame_set(0)
for ob in s.objects:ob.select_set(False)
m.select_set(True);bpy.context.view_layer.objects.active=m
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            space=area.spaces.active;space.shading.type='SOLID';space.overlay.show_bones=False
            space.region_3d.view_location=Vector((0,-.1,1.05))
            space.region_3d.view_rotation=Vector((3,-6,1)).to_track_quat('Z','Y')
            space.region_3d.view_distance=3.4;space.region_3d.view_perspective='ORTHO'
bpy.ops.wm.save_as_mainfile(filepath=str(Path(__file__).resolve().parent/'monster_refined_v020.blend'))

