import bpy
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).resolve().parent
s=bpy.data.scenes['MONSTER_REFINED_V021'];bpy.context.window.scene=s
r=bpy.data.objects['Refined021_Rig'];m=bpy.data.objects['Refined021_Mesh']
for ob in s.objects:
 if ob.type=='MESH' and ob!=m:ob.hide_render=True
for t in r.animation_data.nla_tracks:t.mute=True
s.render.engine='BLENDER_EEVEE';s.render.resolution_x=1000;s.render.resolution_y=1000;s.render.resolution_percentage=100;s.render.image_settings.file_format='PNG'
cam=s.camera;cam.data.type='ORTHO';s.render.film_transparent=False
clay=bpy.data.materials.new('ReviewClay');clay.diffuse_color=(.37,.41,.43,1);clay.use_nodes=True
bs=clay.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.37,.41,.43,1);bs.inputs['Roughness'].default_value=.72
lightdata=bpy.data.lights.new('HandReviewSoftbox','AREA');lightdata.energy=25;lightdata.shape='DISK';lightdata.size=1
light=bpy.data.objects.new('HandReviewSoftbox',lightdata);s.collection.objects.link(light)
for clip in ['REST','idle','grab_stand_hold']:
 r.data.pose_position='REST' if clip=='REST' else 'POSE'
 if clip!='REST':
  a=next(t.strips[0].action for t in r.animation_data.nla_tracks if t.name==clip);r.animation_data.action=a;r.animation_data.action_slot=a.slots[0]
 s.frame_set(0);bpy.context.view_layer.update()
 def at(name):return r.data.bones[name+'_L'].head_local.copy() if clip=='REST' else r.pose.bones[name+'_L'].head.copy()
 wrist=at('hand');forward=(at('middle_01')-wrist).normalized();x=at('thumb_01')-at('middle_01');x=(x-forward*x.dot(forward)).normalized();palm=forward.cross(x)
 center=wrist+forward*.18
 for view,direction in [('palm',palm),('back',-palm),('side',x),('oblique',palm*.75+x*.65)]:
  cam.location=center+direction.normalized()*2;cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.45
  light.location=center+direction*.65-forward*.25+x*.2;light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
  s.view_layers[0].material_override=clay
  s.render.filepath=str(OUT/(clip+'_'+view+'_clay.png'));bpy.ops.render.render(write_still=True)
  if view=='oblique':
   s.view_layers[0].material_override=None
   s.render.filepath=str(OUT/(clip+'_skin.png'));bpy.ops.render.render(write_still=True)
s.view_layers[0].material_override=None
r.data.pose_position='POSE';a=next(t.strips[0].action for t in r.animation_data.nla_tracks if t.name=='idle');r.animation_data.action=a;r.animation_data.action_slot=a.slots[0];s.frame_set(0)
center=Vector((0,-.1,1.05));cam.location=center+Vector((0,-5,.15));cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.55;light.hide_render=True
s.render.filepath=str(OUT/'idle_full.png');bpy.ops.render.render(write_still=True)
