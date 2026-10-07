import bpy
s=bpy.data.scenes['BARREL_VFX_AUTHORING']
bpy.context.window.scene=s
nt=bpy.data.materials['BakedFuelVolume'].node_tree
emission=[n for n in nt.nodes if n.type=='MATH'][1]
# Avoid late cache bounds; retain the useful expanding, turbulent plume.
for index in range(64):
 frame=1+round(index*75/63)
 s.frame_set(frame)
 emission.inputs[1].default_value=0
 s.render.filepath='C:/Users/evan4/Projects/ApocalypseRV/.godot/art-work/barrel-vfx/realism/frames/smoke_'+str(index).zfill(2)+'.png'
 bpy.ops.render.render(write_still=True)
 if index<24:
  # Tight fire framing doubles useful pixel density without a larger atlas.
  s.camera.data.ortho_scale=4; s.camera.location.z=1
  s.render.filepath='C:/Users/evan4/Projects/ApocalypseRV/.godot/art-work/barrel-vfx/realism/frames/fire_base_'+str(index).zfill(2)+'.png'
  bpy.ops.render.render(write_still=True)
  emission.inputs[1].default_value=2.2
  s.render.filepath='C:/Users/evan4/Projects/ApocalypseRV/.godot/art-work/barrel-vfx/realism/frames/fire_beauty_'+str(index).zfill(2)+'.png'
  bpy.ops.render.render(write_still=True)
  s.camera.data.ortho_scale=8; s.camera.location.z=3
 print('ATLAS_FRAME',index,flush=True)
emission.inputs[1].default_value=2.2
s.frame_set(16)
bpy.ops.wm.save_as_mainfile(filepath='C:/Users/evan4/Projects/ApocalypseRV/art_source/barrel_vfx/barrel_blast.blend')
print('ATLAS_RENDERS_COMPLETE')

