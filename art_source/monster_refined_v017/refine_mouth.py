"""Clone v016, preserve rig/actions, add a readable rotten mouth for close bites."""
import bpy
import bmesh
import math
from mathutils import Vector
source=bpy.data.scenes['MONSTER_REFINED_V016']
scene=bpy.data.scenes.new('MONSTER_REFINED_V017')
scene.render.fps=60
scene.world=source.world.copy()
bpy.context.window.scene=scene
rig=bpy.data.objects['Refined016_Rig'].copy()
rig.data=rig.data.copy()
rig.name='Refined017_Rig'
scene.collection.objects.link(rig)
mesh=bpy.data.objects['Refined016_Mesh'].copy()
mesh.data=mesh.data.copy()
mesh.name='Refined017_Mesh'
mesh.parent=rig
scene.collection.objects.link(mesh)
for modifier in mesh.modifiers:
    if modifier.type=='ARMATURE': modifier.object=rig
for ob in source.objects:
    if ob.name.startswith('Review016_'):
        copy=ob.copy(); copy.data=ob.data.copy()
        copy.name=ob.name.replace('016','017')
        scene.collection.objects.link(copy)
        if copy.type=='CAMERA': scene.camera=copy
for track in rig.animation_data.nla_tracks:
    track.mute=True
    strip=track.strips[0]
    action=strip.action.copy()
    action.name='raker_v017_'+track.name
    strip.action=action
    strip.action_slot=action.slots[0]
rig.animation_data.action=None
rig.data.pose_position='REST'
# Warped, rounded lip edge and a recessed oral bowl replace the jagged black stripe.
oral=mesh.data.materials[2].copy()
oral.name='Raker017_OralLining'
mesh.data.materials[2]=oral
shader=next(n for n in oral.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
shader.inputs['Roughness'].default_value=.36
for polygon in mesh.data.polygons:
    c=polygon.center
    if abs(c.x)<.047 and c.y<-.13 and 2.001<c.z<2.023: polygon.material_index=2
    if polygon.material_index==2: polygon.use_smooth=True

def material(name, color, roughness):
    mat=bpy.data.materials.new(name)
    mat.use_nodes=True
    shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    image=bpy.data.images.new(name+'_Color',width=4,height=4)
    pixels=[]
    for i in range(16):
        factor=.86+.14*((i*7)%11)/10
        pixels.extend([color[0]*factor,color[1]*factor,color[2]*factor,1])
    image.pixels[:]=pixels
    image.pack()
    texture=mat.node_tree.nodes.new('ShaderNodeTexImage'); texture.image=image
    mat.node_tree.links.new(texture.outputs['Color'],shader.inputs['Base Color'])
    shader.inputs['Roughness'].default_value=roughness
    return mat

gum=material('Raker017_DecayedLip',(.095,.058,.043),.48)
tooth=material('Raker017_StainedTeeth',(.50,.39,.23),.40)
flesh=material('Raker017_Tongue',(.075,.025,.022),.33)
parts=[]
def part(name, vertices, faces, mat, bone):
    data=bpy.data.meshes.new(name)
    data.from_pydata(vertices,[],faces); data.update()
    ob=bpy.data.objects.new(name,data); scene.collection.objects.link(ob)
    data.materials.append(mat)
    uv=data.uv_layers.new(name='UVMap')
    for loop in data.loops: uv.data[loop.index].uv=((loop.vertex_index%7)/6,(loop.vertex_index%5)/4)
    for polygon in data.polygons: polygon.use_smooth=True
    group=ob.vertex_groups.new(name=bone)
    group.add(list(range(len(vertices))),1,'REPLACE')
    parts.append(ob)
    return ob

# Two separate lip arcs follow skull/jaw, so the corners open without a rigid ring.
for lower in [False,True]:
    vertices=[]; faces=[]
    for i in range(25):
        x=-.048+.096*i/24
        arch=max(0,1-(x/.049)**2)
        y=-.193+.021*(x/.049)**2
        z=2.007-.0015*arch if lower else 2.019+.003*arch
        for j in range(8):
            theta=math.tau*j/8
            radius=.0026*(.65+.35*arch)
            vertices.append((x,y+math.cos(theta)*radius,z+math.sin(theta)*radius))
        if i:
            for j in range(8):
                a=(i-1)*8+j; b=(i-1)*8+(j+1)%8
                faces.append((a,b,b+8,a+8))
    part('LowerLip' if lower else 'UpperLip',vertices,faces,gum,'jaw' if lower else 'head')
    # Staggered, chipped teeth; lower row sits behind the upper when closed.
    for i in range(9):
        x=(i-4)*.0093+(.003 if lower else 0)
        y=(-.190 if lower else -.200)+.011*(x/.046)**2
        base=2.006 if lower else 2.019
        length=1.35*(.006+(.004 if i in [1,7] else .002*((i*3)%4)/3))
        tip=base+length if lower else base-length
        radius=.0031
        vertices=[]; faces=[]
        for level in range(3):
            z=base+(tip-base)*[0,.70,1][level]
            r=radius*[1,.65,.23][level]
            for j in range(6):
                a=math.tau*j/6
                vertices.append((x+math.cos(a)*r,y+math.sin(a)*r*.75,z))
        faces.append(tuple(reversed(range(6))))
        for level in range(2):
            for j in range(6):
                a=level*6+j; b=level*6+(j+1)%6
                faces.append((a,b,b+6,a+6))
        faces.append(tuple(range(12,18)))
        part(('LowerTooth' if lower else 'UpperTooth')+str(i),vertices,faces,tooth,'jaw' if lower else 'head')
# Low tongue with a center groove, visible only when the jaw opens.
vertices=[];faces=[]
for i in range(9):
    x=(i-4)*.0048
    for j in range(7):
        y=-.17+.023*j/6
        z=2.002+.0015*(1-(x/.022)**2)-.0008*math.exp(-(x/.004)**2)
        vertices.append((x,y,z))
        if i and j: faces.append(((i-1)*7+j-1,(i-1)*7+j,i*7+j,i*7+j-1))
part('Tongue',vertices,faces,flesh,'jaw')
for ob in scene.objects: ob.select_set(False)
mesh.select_set(True)
for ob in parts: ob.select_set(True)
bpy.context.view_layer.objects.active=mesh
bpy.ops.object.join()
bm=bmesh.new(); bm.from_mesh(mesh.data)
bmesh.ops.recalc_face_normals(bm,faces=[f for f in bm.faces if f.material_index==4])
bm.to_mesh(mesh.data); bm.free(); mesh.data.update()
rig.data.pose_position='POSE'
rig.animation_data.action=next(t.strips[0].action for t in rig.animation_data.nla_tracks if t.name=='grab_stand_bite')
rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(13)
scene.camera.location=(.3,-1.8,1.65)
scene.camera.rotation_euler=(Vector((0,-.25,1.64))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.camera.data.ortho_scale=.50
scene.render.resolution_x=800;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.render.engine='BLENDER_EEVEE'
scene.render.image_settings.file_format='PNG'
scene.render.filepath='C:/Users/evan4/Projects/ApocalypseRV/art_source/monster_refined_v017/mouth_review.png'
bpy.ops.render.render(write_still=True)
print('V017',len(mesh.data.vertices),'vertices',len(mesh.data.materials),'materials')
