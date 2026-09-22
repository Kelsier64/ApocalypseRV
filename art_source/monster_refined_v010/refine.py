"""Run through Blender MCP with raker_animated_v008 or its review copy open.
Creates an independent v010 scene; source rigs, actions and mesh remain intact.
"""
import bpy
import bmesh
import math
import json
from mathutils import Vector
from mathutils import noise

OUT = 'C:/Users/evan4/Projects/ApocalypseRV/art_source/monster_refined_v010/'
previous = bpy.data.scenes.get('MONSTER_REFINED_V010')
if previous:
    assert previous.get('source') == 'raker_animated_v008; original scenes and actions preserved'
    bpy.context.window.scene = bpy.data.scenes['RAKER_GAME_EXPORT']
    for ob in list(previous.objects): bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.scenes.remove(previous)
scene = bpy.data.scenes.new('MONSTER_REFINED_V010')
scene.render.fps = 30
bpy.context.window.scene = scene
rig = bpy.data.objects['Raker_Rig'].copy()
rig.data = rig.data.copy()
rig.name = 'Refined010_Rig'
scene.collection.objects.link(rig)
mesh = bpy.data.objects['Raker_Mesh'].copy()
mesh.data = mesh.data.copy()
mesh.name = 'Refined010_Mesh'
mesh.parent = rig
scene.collection.objects.link(mesh)
for mod in mesh.modifiers:
    if mod.type == 'ARMATURE': mod.object = rig
for track in rig.animation_data.nla_tracks: track.mute = True
rig.animation_data.action = bpy.data.actions['raker_idle']
rig.animation_data.action_slot = rig.animation_data.action.slots[0]
scene.frame_set(0)

# One linear subdivision retains UVs and interpolates existing skin weights.
# Sculpt the added vertices instead of smoothing away the low-poly silhouette.
bm = bmesh.new()
bm.from_mesh(mesh.data)
arm_indices={g.index for g in mesh.vertex_groups if 'arm_' in g.name or 'clavicle_' in g.name}
detail_ids={v.index for v in mesh.data.vertices if v.co.z>1.1 and abs(v.co.x)<.16 and not any(g.group in arm_indices and g.weight>.001 for g in v.groups)}
bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if all(v.index in detail_ids for v in f.verts)])
detail_edges=[e for e in bm.edges if all(v.index in detail_ids for v in e.verts)]
bmesh.ops.subdivide_edges(bm, edges=detail_edges, cuts=1, use_grid_fill=True)
bm.to_mesh(mesh.data)
bm.free()

def gauss(x, center, width):
    return math.exp(-((x-center)/width)**2)

def weights(v):
    return {mesh.vertex_groups[g.group].name:g.weight for g in v.groups}

for v in mesh.data.vertices:
    x,y,z = v.co
    w = weights(v)
    torso = sum(w.get(n,0) for n in ['pelvis','spine_01','spine_02','spine_03','hump'])
    arm_blend=sum(value for name,value in w.items() if 'arm_' in name or 'clavicle_' in name)
    torso *= max(0,1-arm_blend*8)
    head = w.get('head',0)
    neck = w.get('neck_01',0)+w.get('neck_02',0)
    if torso > .1:
        front = gauss(y,-.055,.080)
        back = gauss(y,.145,.085)
        # Pinched waist, outward rib cage and iliac crest.
        v.co.x += x*torso*(-.11*gauss(z,1.36,.12)+.10*gauss(z,1.65,.14)+.035*gauss(z,1.15,.06))
        v.co.y += torso*front*(.018*gauss(z,1.39,.13)*gauss(x,0,.10)-.008*gauss(x,0,.023)*gauss(z,1.67,.17))
        # Paired scapulae, central spinal groove and hunched trapezius mass.
        v.co.y += torso*back*(.036*gauss(abs(x),.105,.055)*gauss(z,1.71,.12)+.052*gauss(x,0,.095)*gauss(z,1.84,.10)-.010*gauss(x,0,.018)*gauss(z,1.62,.20))
        v.co.z += torso*back*.022*gauss(z,1.81,.10)*gauss(x,0,.20)
        for height in [1.48,1.535,1.59,1.645]:
            rib = gauss(z,height+.10*abs(x),.012)*gauss(abs(x),.09,.08)
            v.co.y -= torso*front*.006*rib
    if head > .1:
        # Lengthened lower face, narrower temples, a low brow and recessed sockets.
        v.co.x *= 1-head*(.09+.06*gauss(z,2.025,.055))
        v.co.y -= .060*head
        face = gauss(y,-.135,.025)
        eye = gauss(abs(x),.045,.025)*gauss(z,2.076,.021)
        brow = gauss(abs(x),.046,.045)*gauss(z,2.109,.013)
        cheek = gauss(abs(x),.069,.025)*gauss(z,2.030,.024)
        v.co.y += head*face*(.006*eye-.006*brow-.005*cheek)
        v.co.z -= .010*head*gauss(z,2.009,.033)
    if neck > .1:
        v.co.y -= .035*neck
        v.co.x *= 1-.10*neck
    # Raised knuckles / dorsal tendons without changing finger lengths or joints.
    for side in ['L','R']:
        hand_weight = w.get('hand_'+side,0)
        if hand_weight > .1:
            v.co.y += .0015*hand_weight*gauss(y,-.055,.020)
        forearm = w.get('forearm_'+side,0)
        if forearm > .1:
            v.co.y += .003*forearm*gauss(y,.015,.035)*gauss(z,1.03,.18)
mesh.data.update()

# Spatial coloration follows anatomy and is stored on the mesh, so it deforms
# with the skin. No world-space swimming; glTF can export this color attribute.
colors = mesh.data.color_attributes.new(name='RakerSkin',type='FLOAT_COLOR',domain='POINT')
for v in mesh.data.vertices:
    x,y,z=v.co
    w=weights(v)
    broad=noise.noise(Vector((x*12+3,y*12-2,z*12)))
    medium=noise.noise(Vector((x*48,y*48+8,z*48)))
    fine=noise.noise(Vector((x*125,y*125,z*125)))
    tone=.34+.105*broad+.048*medium+.018*fine
    torso=sum(w.get(n,0) for n in ['pelvis','spine_01','spine_02','spine_03'])
    tone-=torso*.042*gauss(x,0,.055)*gauss(z,1.44,.20)*gauss(y,-.04,.07)
    tone-=w.get('head',0)*.11*gauss(abs(x),.042,.025)*gauss(z,2.076,.025)*gauss(y,-.14,.030)
    tone-=.023*gauss(z,.55,.035)
    # Distal phalanges become dry dark horn, blending into the skin.
    tip=0
    for name,weight in w.items():
        if '_02_' in name and any(f in name for f in ['index','middle','ring','pinky','thumb']):
            bone=rig.data.bones.get(name)
            t=(v.co-bone.head_local).dot(bone.tail_local-bone.head_local)/(bone.length**2)
            tip=max(tip,weight*max(0,min(1,(t-.62)/.42)))
    tone*=1-.45*tip
    tone=max(.075,min(.55,tone))
    colors.data[v.index].color=(tone*1.06,tone*1.015,tone*.91,1)
mesh.data.color_attributes.active_color = colors

skin=bpy.data.materials.new('Raker010_AshenSkin')
skin.use_nodes=True
bsdf=next(n for n in skin.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
bsdf.inputs['Base Color'].default_value=(1,1,1,1)
bsdf.inputs['Roughness'].default_value=.88
vc=skin.node_tree.nodes.new('ShaderNodeVertexColor')
vc.layer_name='RakerSkin'
skin.node_tree.links.new(vc.outputs['Color'],bsdf.inputs['Base Color'])
# Fine mottling supplements vertex-level anatomical color. It will be baked to
# the existing UV map for portable export after deformation validation.
tex=skin.node_tree.nodes.new('ShaderNodeTexNoise')
tex.noise_dimensions='3D'
tex.noise_type='FBM'
tex.inputs['Scale'].default_value=46
tex.inputs['Detail'].default_value=3
tex.inputs['Roughness'].default_value=.72
ramp=skin.node_tree.nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position=.25
ramp.color_ramp.elements[0].color=(.27,.25,.22,1)
ramp.color_ramp.elements[1].position=.72
ramp.color_ramp.elements[1].color=(1.20,1.16,1.08,1)
mix=skin.node_tree.nodes.new('ShaderNodeMixRGB')
mix.blend_type='MULTIPLY'
mix.inputs['Fac'].default_value=.82
skin.node_tree.links.new(tex.outputs['Fac'],ramp.inputs['Fac'])
skin.node_tree.links.new(vc.outputs['Color'],mix.inputs['Color1'])
skin.node_tree.links.new(ramp.outputs['Color'],mix.inputs['Color2'])
skin.node_tree.links.new(mix.outputs['Color'],bsdf.inputs['Base Color'])
socket=mesh.data.materials[1].copy()
socket.name='Raker010_RecessedEyes'
eye_bsdf=next(n for n in socket.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
eye_bsdf.inputs['Base Color'].default_value=(.007,.008,.007,1)
eye_bsdf.inputs['Roughness'].default_value=.97
material_indices=[p.material_index for p in mesh.data.polygons]
mesh.data.materials.clear()
mesh.data.materials.append(skin)
mesh.data.materials.append(socket)
for p,index in zip(mesh.data.polygons,material_indices): p.material_index=index
for p in mesh.data.polygons: p.use_smooth=False

# Copy only the existing review stage, not another creature.
for name in ['Refined_Review_Camera','Refined_Key','Refined_Fill','Refined_Rim','Refined_Ground']:
    ob=bpy.data.objects[name].copy()
    ob.data=ob.data.copy()
    ob.name='Review010_'+name
    scene.collection.objects.link(ob)
    if ob.type=='CAMERA': scene.camera=ob
scene.world=bpy.data.scenes['MONSTER_REFINED_V009'].world.copy()
try: scene.render.engine='BLENDER_EEVEE'
except TypeError: pass
scene.render.resolution_x=900
scene.render.resolution_y=1000
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.filepath=OUT+'threequarter.png'
scene.camera.location=(3,-6,2.65)
scene.camera.rotation_euler=(Vector((0,0,1.10))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.camera.data.type='ORTHO'
scene.camera.data.ortho_scale=2.65
scene['source']='raker_animated_v008; original scenes and actions preserved'
scene['revision']='v010: anatomical sculpt and ash skin color; 2.18 m, 22 original clips'
scene['reference']='User supplied ChatGPT Image 2026年9月21日 下午11_32_02.png'
for ob in scene.objects: ob.select_set(False)
mesh.select_set(True)
bpy.context.view_layer.objects.active=mesh
mesh.data.calc_loop_triangles()
print('REFINED',len(mesh.data.vertices),len(mesh.data.loop_triangles),min(v.co.z for v in mesh.data.vertices),max(v.co.z for v in mesh.data.vertices))
bpy.ops.wm.save_as_mainfile(filepath=OUT+'monster_refined_v010.blend')
bpy.ops.render.render(write_still=True)
