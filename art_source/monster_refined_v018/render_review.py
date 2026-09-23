import bpy
from mathutils import Vector
OUT='C:/Users/evan4/Projects/ApocalypseRV/art_source/monster_refined_v018/'
s=bpy.data.scenes['MONSTER_REFINED_V018'];bpy.context.window.scene=s;r=bpy.data.objects['Refined018_Rig']
for t in r.animation_data.nla_tracks:t.mute=True
r.animation_data.action=next(t.strips[0].action for t in r.animation_data.nla_tracks if t.name=='grab_stand_bite');r.animation_data.action_slot=r.animation_data.action.slots[0]
for name,frame in [('closed',0),('open',14)]:
 s.frame_set(frame);bpy.context.view_layer.update()
 pose=r.pose.bones['head'].matrix@r.data.bones['head'].matrix_local.inverted()
 focus=pose@Vector((0,-.08,2.04))
 s.camera.location=focus+pose.to_3x3()@Vector((.08,-1,.035))
 s.camera.rotation_euler=(focus-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.ortho_scale=.34
 s.render.filepath=OUT+'mouth_'+name+'.png';bpy.ops.render.render(write_still=True)
