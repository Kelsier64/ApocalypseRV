"""Run through Blender MCP in the user's live Blender; retains other scenes."""
import bpy
import math
from mathutils import Vector

ROOT = 'C:/Users/evan4/Projects/ApocalypseRV/'
scene = bpy.data.scenes.new('BARREL_MAN_AUTHORING')
bpy.context.window.scene = scene
scene.render.fps = 60
scene.frame_start = 1
scene.frame_end = 61
scene.world = bpy.data.worlds.new('BarrelMan_Studio')
scene.world.use_nodes = True
scene.world.node_tree.nodes.get('Background').inputs[0].default_value = (.16, .19, .23, 1)
scene.world.node_tree.nodes.get('Background').inputs[1].default_value = .45

bpy.ops.import_scene.gltf(filepath=ROOT+'assets/models/oil_barrel/oil_barrel.glb')
barrel = next(o for o in bpy.context.selected_objects if o.type == 'MESH')
barrel.name = 'Barrel_Reference'
barrel.location = (0, 0, 1.4)

skin = bpy.data.materials.new('BarrelMan_DirtySkin')
skin.use_nodes = True
nodes = skin.node_tree.nodes
links = skin.node_tree.links
bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
bsdf.inputs['Roughness'].default_value = .76
noise = nodes.new('ShaderNodeTexNoise')
noise.inputs['Scale'].default_value = 17
noise.inputs['Detail'].default_value = 4
noise.inputs['Roughness'].default_value = .72
coord = nodes.new('ShaderNodeTexCoord')
links.new(coord.outputs['Object'], noise.inputs['Vector'])
ramp = nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position = .26
ramp.color_ramp.elements[0].color = (.085, .045, .025, 1)
ramp.color_ramp.elements[1].position = .76
ramp.color_ramp.elements[1].color = (.48, .29, .185, 1)
mid = ramp.color_ramp.elements.new(.49)
mid.color = (.27, .135, .073, 1)
links.new(noise.outputs['Fac'], ramp.inputs[0])
links.new(ramp.outputs[0], bsdf.inputs['Base Color'])
nail_material = bpy.data.materials.new('BarrelMan_DirtyNails')
nail_material.diffuse_color = (.31, .265, .185, 1)
nail_material.use_nodes = True
np = next(n for n in nail_material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
np.inputs['Base Color'].default_value = (.31, .265, .185, 1)
np.inputs['Roughness'].default_value = .67

def ellipse(name, position, scale, pieces):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, location=position)
    ob = bpy.context.object
    ob.name = name
    ob.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    pieces.append(ob)
    return ob

legs = []
nails = []
for side, suffix in [(-1, 'R'), (1, 'L')]:
    x = side*.145
    # Anatomical cross-sections: separate quadriceps, narrow knee, calf belly,
    # tibial ridge and Achilles taper. Front is Blender -Y / glTF +Z.
    profiles = [
        (1.045,.105,.099,.030),(.99,.115,.105,.028),(.94,.123,.111,.024),
        (.87,.121,.110,.018),(.80,.115,.103,.016),(.73,.106,.096,.010),
        (.66,.095,.084,.002),(.60,.083,.072,-.013),(.55,.076,.066,-.025),
        (.51,.075,.067,-.026),(.47,.066,.060,-.011),(.43,.065,.060,.008),
        (.39,.078,.073,.027),(.35,.085,.079,.039),(.31,.081,.076,.042),
        (.27,.071,.065,.039),(.23,.058,.053,.030),(.19,.045,.043,.020),
        (.155,.038,.038,.012),(.12,.036,.038,.008),(.085,.037,.040,.010)]
    verts = []
    faces = []
    segments = 32
    for z, rx, ry, cy in profiles:
        for k in range(segments):
            angle = k*math.tau/segments
            tibia = max(0, -math.sin(angle))**12 * .008 if .22 < z < .45 else 0
            asym = 1 + .04*side*math.cos(angle)
            verts.append((x+rx*math.cos(angle)*asym, cy+ry*math.sin(angle)-tibia, z))
    for j in range(len(profiles)-1):
        for k in range(segments):
            a=j*segments+k
            b=j*segments+(k+1)%segments
            faces.append((a,b,b+segments,a+segments))
    faces.append(tuple(reversed(range(segments))))
    faces.append(tuple((len(profiles)-1)*segments+k for k in range(segments)))
    mesh=bpy.data.meshes.new('LegAnatomy_'+suffix)
    mesh.from_pydata(verts,[],faces)
    mesh.update()
    leg=bpy.data.objects.new('Leg_'+suffix,mesh)
    scene.collection.objects.link(leg)
    pieces=[leg]
    ellipse('Patella', (x,-.076,.519), (.055,.025,.049), pieces)
    ellipse('MedialAnkle', (x-side*.034,.006,.149), (.019,.024,.027), pieces)
    ellipse('LateralAnkle', (x+side*.035,.006,.134), (.018,.022,.025), pieces)
    ellipse('Heel', (x,.041,.064), (.057,.083,.060), pieces)
    ellipse('Instep', (x,-.029,.071), (.057,.102,.066), pieces)
    ellipse('BallOfFoot', (x,-.125,.050), (.077,.064,.045), pieces)
    toe_data=[(-.052,-.207,.025,.060),(-.014,-.218,.018,.055),(.019,-.210,.017,.049),(.048,-.197,.015,.041),(.071,-.179,.013,.033)]
    for idx,(offset,y,radius,length) in enumerate(toe_data):
        toe=ellipse('Toe_%d_%s'%(idx+1,suffix),(x+side*offset,y,.037),(radius,length,.029 if idx==0 else .023),pieces)
        nail_parts=[]
        nail=ellipse('Nail_%d_%s'%(idx+1,suffix),(x+side*offset,y-length*.38,.060 if idx==0 else .054),(radius*.66,length*.29,.0045),nail_parts)
        nail.data.materials.append(nail_material)
        nails.append((nail,suffix))
    bpy.ops.object.select_all(action='DESELECT')
    for ob in pieces: ob.select_set(True)
    bpy.context.view_layer.objects.active=leg
    bpy.ops.object.join()
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    remesh=leg.modifiers.new('Anatomical_union','REMESH')
    remesh.mode='VOXEL'
    remesh.voxel_size=.0065
    remesh.use_smooth_shade=True
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    smooth=leg.modifiers.new('Skin_relax','SMOOTH')
    smooth.factor=.42
    smooth.iterations=3
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    decimate=leg.modifiers.new('Game_topology','DECIMATE')
    decimate.ratio=.57
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    # Flatten the load-bearing sole and form the medial arch.
    for v in leg.data.vertices:
        compression=max(0,min(1,(v.co.z-.19)/.15))
        # Human leg widths, retaining the unscaled joint centres and feet.
        center_y=min([(abs(row[0]-v.co.z),row[3]) for row in profiles])[1]
        v.co.x=x+(v.co.x-x)*(1-.15*compression)
        v.co.y=center_y+(v.co.y-center_y)*(1-.18*compression)
        # The concealed upper-thigh seam ends just inside the barrel floor;
        # an unnecessary long capped extension would poke out when folded.
        if v.co.z>.94: v.co.z=.94+(v.co.z-.94)*.35
        if v.co.z<.022:
            v.co.z=.016
        if -.10<v.co.y<-.015 and (v.co.x-x)*side<-.025 and v.co.z<.043:
            v.co.z=max(v.co.z,.023+.009*math.sin((v.co.y+.10)/.085*math.pi))
    for p in leg.data.polygons: p.use_smooth=True
    leg.data.materials.clear()
    leg.data.materials.append(skin)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.015)
    bpy.ops.object.mode_set(mode='OBJECT')
    legs.append(leg)

# Pack both legs in distinct UV halves for one shared 1K texture.
for index,leg in enumerate(legs):
    for uv in leg.data.uv_layers.active.data:
        uv.uv.x=uv.uv.x*.48+.01+index*.5
image=bpy.data.images.new('BarrelMan_Skin_BaseColor',width=1024,height=1024,alpha=False)
image.generated_color=(.27,.135,.073,1)
image_node=nodes.new('ShaderNodeTexImage')
image_node.image=image
nodes.active=image_node
scene.render.engine='CYCLES'
scene.cycles.samples=1
scene.render.bake.use_pass_direct=False
scene.render.bake.use_pass_indirect=False
scene.render.bake.use_pass_color=True
scene.render.bake.margin=8
scene.render.bake.use_clear=True
for i,leg in enumerate(legs):
    bpy.ops.object.select_all(action='DESELECT')
    leg.select_set(True)
    bpy.context.view_layer.objects.active=leg
    scene.render.bake.use_clear=(i==0)
    bpy.ops.object.bake(type='DIFFUSE')
image.filepath_raw=ROOT+'art_source/barrel_man/skin_basecolor.png'
image.file_format='PNG'
image.save()
image.pack()
links.new(image_node.outputs['Color'],bsdf.inputs['Base Color'])
scene.render.engine='BLENDER_EEVEE'

bpy.ops.object.select_all(action='DESELECT')
arm_data=bpy.data.armatures.new('BarrelManSkeleton')
rig=bpy.data.objects.new('BarrelManRig',arm_data)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active=rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
def bone(name, head, tail, parent=None):
    b=arm_data.edit_bones.new(name)
    b.head=head
    b.tail=tail
    if parent: b.parent=arm_data.edit_bones[parent]
    return b
bone('root',(0,0,0),(0,0,.1))
bone('pelvis',(0,0,.94),(0,0,1.06),'root')
bone('barrel',(0,0,1.4),(0,0,1.6),'root')
for side,suffix in [(-1,'R'),(1,'L')]:
    x=side*.145
    bone('thigh_'+suffix,(x,.02,.94),(x,-.025,.515),'pelvis')
    bone('shin_'+suffix,(x,-.025,.515),(x,.008,.115),'thigh_'+suffix)
    bone('foot_'+suffix,(x,.008,.115),(x,-.135,.043),'shin_'+suffix)
    bone('toes_'+suffix,(x,-.135,.043),(x,-.252,.038),'foot_'+suffix)
bpy.ops.object.mode_set(mode='OBJECT')
for leg,suffix in zip(legs,['R','L']):
    groups={name:leg.vertex_groups.new(name=name+'_'+suffix) for name in ['thigh','shin','foot','toes']}
    for v in leg.data.vertices:
        z=v.co.z
        if z>.60: weights={'thigh':1.0}
        elif z>.44:
            t=max(0,min(1,(z-.44)/.16))
            weights={'thigh':t,'shin':1-t}
        elif z>.20: weights={'shin':1.0}
        elif z>.09:
            t=max(0,min(1,(z-.09)/.11))
            weights={'shin':t,'foot':1-t}
        elif v.co.y<-.11:
            t=max(0,min(1,(-v.co.y-.11)/.06))
            weights={'foot':1-t,'toes':t}
        else: weights={'foot':1.0}
        for name,w in weights.items():
            if w>0: groups[name].add([v.index],w,'REPLACE')
    mod=leg.modifiers.new('Skin','ARMATURE')
    mod.object=rig
    leg.parent=rig
for nail,suffix in nails:
    vg=nail.vertex_groups.new(name='toes_'+suffix)
    vg.add(list(range(len(nail.data.vertices))),1.0,'REPLACE')
    # Apply world-space placement before using the same deformation matrix.
    bpy.ops.object.select_all(action='DESELECT')
    nail.select_set(True)
    bpy.context.view_layer.objects.active=nail
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    mod=nail.modifiers.new('Skin','ARMATURE')
    mod.object=rig
    nail.parent=rig
# Reference barrel rigidly weighted to its own bone (excluded from runtime GLB).
bpy.ops.object.select_all(action='DESELECT')
barrel.select_set(True)
bpy.context.view_layer.objects.active=barrel
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
vg=barrel.vertex_groups.new(name='barrel')
vg.add(list(range(len(barrel.data.vertices))),1.0,'REPLACE')
mod=barrel.modifiers.new('Rigid_barrel_attachment','ARMATURE')
mod.object=rig
barrel.parent=rig
rig.show_in_front=True
for pb in rig.pose.bones: pb.rotation_mode='QUATERNION'
scene.frame_set(1)
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active=rig
print('Created:',[(o.name,len(o.data.polygons)) for o in legs], 'bones',len(arm_data.bones))
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'art_source/barrel_man/barrel_man.blend',copy=True)
