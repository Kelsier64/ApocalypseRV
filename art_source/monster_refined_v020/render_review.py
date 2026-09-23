"""Close-up front view shows inward/outward finger hinges; no helper material."""
import bpy
from mathutils import Vector
from pathlib import Path
OUT=Path(__file__).resolve().parent
for version in ['019','020']:
 s=bpy.data.scenes['MONSTER_REFINED_V'+version];bpy.context.window.scene=s
 r=bpy.data.objects['Refined'+version+'_Rig'];m=bpy.data.objects['Refined'+version+'_Mesh']
 for t in r.animation_data.nla_tracks:t.mute=True
 s.render.engine='BLENDER_EEVEE';s.render.resolution_x=1100;s.render.resolution_y=850;s.render.resolution_percentage=100;s.render.image_settings.file_format='PNG'
 cam=s.camera;cam.data.type='ORTHO'
 for clip in ['REST','idle','walk','grab_stand_hold']:
  r.data.pose_position='REST' if clip=='REST' else 'POSE'
  if clip!='REST':
   a=next(t.strips[0].action for t in r.animation_data.nla_tracks if t.name==clip);r.animation_data.action=a;r.animation_data.action_slot=a.slots[0]
  s.frame_set(0 if clip!='walk' else 18);bpy.context.view_layer.update()
  if clip=='REST':point=r.data.bones['middle_02_L'].head_local.copy()
  else:point=r.pose.bones['middle_02_L'].head.copy()
  cam.location=point+Vector((.04,-3,.015));cam.rotation_euler=(point-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.5
  if clip=='grab_stand_hold':
   cam.location=point+Vector((3,0,0));cam.rotation_euler=(point-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.65
  s.render.filepath=str(OUT/(version+'_'+clip+'_fingers.png'));bpy.ops.render.render(write_still=True)
 # Full idle front: both hands relative to torso.
 r.data.pose_position='POSE';a=next(t.strips[0].action for t in r.animation_data.nla_tracks if t.name=='idle');r.animation_data.action=a;r.animation_data.action_slot=a.slots[0];s.frame_set(0)
 focus=Vector((0,-.1,1.05));cam.location=focus+Vector((0,-5,.15));cam.rotation_euler=(focus-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.55
 s.render.filepath=str(OUT/(version+'_idle_front.png'));bpy.ops.render.render(write_still=True)
