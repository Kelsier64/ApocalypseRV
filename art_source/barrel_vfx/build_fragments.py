import bpy, math
from mathutils import Vector
scene=bpy.data.scenes.new('BARREL_FRAGMENT_AUTHORING')
bpy.context.window.scene=scene
blue=bpy.data.materials.new('ScorchedBlueEnamel'); blue.use_nodes=True
p=next(n for n in blue.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
p.inputs['Base Color'].default_value=(.016,.055,.068,1)
p.inputs['Metallic'].default_value=.65
p.inputs['Roughness'].default_value=.58
steel=bpy.data.materials.new('TornBareSteel'); steel.use_nodes=True
p=next(n for n in steel.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
p.inputs['Base Color'].default_value=(.19,.17,.13,1)
p.inputs['Metallic'].default_value=.85
p.inputs['Roughness'].default_value=.55
parts=[]
# Rolled rim and dented lid, visible thickness, no perfect flat disc.
verts=[]; faces=[]
for j,(radius,z) in enumerate([(.025,-.018),(.25,-.006),(.296,.012),(.32,.018),(.329,.005),(.316,-.007)]):
 for i in range(32):
  a=i*math.tau/32
  verts.append((radius*math.cos(a),radius*math.sin(a),z+.025*math.sin(a*2)+.009*math.sin(a*5)))
  if j>0: faces.append(((j-1)*32+i,(j-1)*32+(i+1)%32,j*32+(i+1)%32,j*32+i))
faces.append(tuple(range(31,-1,-1)))
mesh=bpy.data.meshes.new('DentLidMesh'); mesh.from_pydata(verts,[],faces); mesh.update()
lid=bpy.data.objects.new('BarrelLid',mesh); scene.collection.objects.link(lid); parts.append(lid)
# Seven pieces of cylinder wall with torn edges, folded ends and press ribs.
for part in range(7):
 verts=[]; faces=[]
 width=.34+(.04*(part%3)); height=.29+(.045*((part+1)%4))
 for j in range(7):
  for i in range(9):
   u=i/8-.5; v=j/6-.5
   ang=u*width/.33
   edge=(.018*math.sin(j*4.7+part)) if i in [0,8] else 0
   tip=(.018*math.sin(i*5.2+part)) if j in [0,6] else 0
   x=.33*math.sin(ang)+edge
   y=v*height+tip
   z=.33*(1-math.cos(ang))+.022*math.sin(v*math.tau*2+part)
   z+=.065*max(0,(u-.22)*3)**2*((-1)**part)
   verts.append((x,y,z))
   if i>0 and j>0:
    k=j*9+i; faces.append((k-10,k-9,k,k-1))
 mean=Vector((0,0,0))
 for v in verts: mean+=Vector(v)
 mean/=len(verts)
 verts=[tuple(Vector(v)-mean) for v in verts]
 mesh=bpy.data.meshes.new('BentWallMesh'+str(part)); mesh.from_pydata(verts,[],faces); mesh.update()
 ob=bpy.data.objects.new('BarrelShard'+str(part+1).zfill(2),mesh); scene.collection.objects.link(ob); parts.append(ob)
for index,ob in enumerate(parts):
 ob.data.materials.append(blue); ob.data.materials.append(steel)
 for poly in ob.data.polygons:
  poly.use_smooth=True
  if poly.index%11==0: poly.material_index=1
 bpy.context.view_layer.objects.active=ob; ob.select_set(True)
 sol=ob.modifiers.new('TornMetalThickness','SOLIDIFY'); sol.thickness=.005
 sol.material_offset=1; sol.material_offset_rim=1
 bpy.ops.object.modifier_apply(modifier=sol.name)
 bev=ob.modifiers.new('LightCatchingEdges','BEVEL'); bev.width=.002; bev.segments=1
 bpy.ops.object.modifier_apply(modifier=bev.name)
 ob.select_set(False)
# Export only centered pieces. The editable scene is laid out afterwards.
for ob in parts: ob.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.export_scene.gltf(filepath='C:/Users/evan4/Projects/ApocalypseRV/assets/effects/barrel_blast/fragments.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_animations=False)
for index,ob in enumerate(parts):
 ob.location=((index%4)*.9,(index//4)*.9,0)
print('FRAGMENTS',[(ob.name,len(ob.data.polygons)) for ob in parts])
# Standalone rebuilds must not overwrite the canonical combined gas/metal source.
bpy.ops.wm.save_as_mainfile(filepath='C:/Users/evan4/Projects/ApocalypseRV/.godot/art-work/barrel-vfx/realism/fragments_rebuild.blend')

