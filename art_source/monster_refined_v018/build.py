"""Rebuild the native mouth aperture from v016, without v017 exterior parts."""
import bpy, bmesh, math
from mathutils import Vector, Quaternion
OUT='C:/Users/evan4/Projects/ApocalypseRV/art_source/monster_refined_v018/'
source=bpy.data.scenes['MONSTER_REFINED_V016']
scene=bpy.data.scenes.new('MONSTER_REFINED_V018')
scene.render.fps=60
scene.world=source.world.copy()
bpy.context.window.scene=scene
rig=bpy.data.objects['Refined016_Rig'].copy(); rig.data=rig.data.copy()
rig.name='Refined018_Rig'; scene.collection.objects.link(rig)
mesh=bpy.data.objects['Refined016_Mesh'].copy(); mesh.data=mesh.data.copy()
mesh.name='Refined018_Mesh'; mesh.parent=rig; scene.collection.objects.link(mesh)
mesh.data.materials[0]=mesh.data.materials[0].copy()
mesh.data.materials[0].use_backface_culling=True
for modifier in mesh.modifiers:
    if modifier.type=='ARMATURE': modifier.object=rig
for ob in source.objects:
    if ob.name.startswith('Review016_'):
        copy=ob.copy(); copy.data=ob.data.copy(); copy.name=ob.name.replace('016','018')
        scene.collection.objects.link(copy)
        if copy.type=='CAMERA': scene.camera=copy
for track in rig.animation_data.nla_tracks:
    track.mute=True
    strip=track.strips[0]; action=strip.action.copy(); action.name='raker_v018_'+track.name
    strip.action=action; strip.action_slot=action.slots[0]
rig.animation_data.action=None
rig.data.pose_position='REST'
oral=bpy.data.materials.new('Raker018_OralCavity'); oral.use_nodes=True; mesh.data.materials[2]=oral
shader=next(n for n in oral.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
shader.inputs['Base Color'].default_value=(.022,.009,.007,1)
shader.inputs['Roughness'].default_value=.88
shader.inputs['Specular IOR Level'].default_value=.12
bm=bmesh.new(); bm.from_mesh(mesh.data)
region=[f for f in bm.faces if f.calc_center_median().y<-.05 and (f.calc_center_median().x/.046)**2+((f.calc_center_median().z-2.013)/.011)**2<1]
bmesh.ops.delete(bm,geom=region,context='FACES_ONLY')
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
edges=[e for e in bm.edges if e.is_boundary]
adj={}
for edge in edges:
    a,b=edge.verts; adj.setdefault(a,[]).append(b); adj.setdefault(b,[]).append(a)
assert all(len(neighbors)==2 for neighbors in adj.values()),'Mouth boundary must be a closed ring'
ring=[]; previous=None; current=next(iter(adj))
while current not in ring:
    ring.append(current)
    nxt=next(v for v in adj[current] if v!=previous)
    previous,current=current,nxt
assert len(ring)==len(adj),'Unexpected disconnected mouth hole'
deform=bm.verts.layers.deform.verify()
head=mesh.vertex_groups['head'].index; jaw=mesh.vertex_groups['jaw'].index
angles=[math.atan2((v.co.z-2.013)/.011,v.co.x/.046) for v in ring]
# Retain winding, regularize the noisy remeshed boundary before lofting.
winding=sum(math.atan2(math.sin(angles[(i+1)%len(ring)]-a),math.cos(angles[(i+1)%len(ring)]-a)) for i,a in enumerate(angles))
start=angles[0]; sign=math.copysign(1,winding)
angles=[start+sign*a for a in sorted((sign*(a-start))%math.tau for a in angles)]
for face in bm.faces:
    if face.material_index==2: face.material_index=0
# Rebuild a short skin transition from the original boundary, then loft the
# recessed mouth lining. Keep the surrounding face instead of pulling it flat.
uv=bm.loops.layers.uv.active
rim_uv=[v.link_loops[0][uv].uv.copy() for v in ring]
center_uv=sum(rim_uv,Vector((0,0)))/len(rim_uv)
previous_uv=rim_uv
original=[v.co.copy() for v in ring]
def weights(vertex,theta,depth=0):
    lower=max(0,min(1,.5-math.sin(theta)*2.5))
    vertex[deform].clear(); vertex[deform][head]=1-lower; vertex[deform][jaw]=lower
previous_ring=ring
for blend in [.35,.7,1.0]:
    inner=[]
    for i,theta in enumerate(angles):
        lip=Vector((.040*math.cos(theta),-.185+.028*math.cos(theta)**2,2.013+.00001*math.sin(theta)))
        vertex=bm.verts.new(original[i].lerp(lip,blend)); weights(vertex,theta); inner.append(vertex)
    inner_uv=[coord.lerp(center_uv,blend*.6) for coord in rim_uv]
    for i in range(len(ring)):
        j=(i+1)%len(ring)
        face=bm.faces.new((previous_ring[i],previous_ring[j],inner[j],inner[i]));face.material_index=0;face.smooth=True
        for loop,coord in zip(face.loops,[previous_uv[i],previous_uv[j],inner_uv[j],inner_uv[i]]):loop[uv].uv=coord
    previous_ring=inner;previous_uv=inner_uv
for depth in [.1,.35,.65,1.0]:
    inner=[]
    for theta in angles:
        vertex=bm.verts.new((.040*math.cos(theta)*(1-.68*depth),-.185+.028*math.cos(theta)**2+.09*math.sqrt(depth),2.013+.026*math.sin(theta)*min(1,depth*10)))
        weights(vertex,theta,depth); inner.append(vertex)
    for i in range(len(ring)):
        face=bm.faces.new((previous_ring[i],previous_ring[(i+1)%len(ring)],inner[(i+1)%len(ring)],inner[i]))
        face.material_index=2; face.smooth=True
    previous_ring=inner
center=bm.verts.new((0,-.075,2.013)); weights(center,0,1)
for i in range(len(ring)):
    face=bm.faces.new((previous_ring[i],previous_ring[(i+1)%len(ring)],center)); face.material_index=2; face.smooth=True
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bm.to_mesh(mesh.data); bm.free(); mesh.data.update()
print('Native mouth ring',len(ring),'body vertices',len(mesh.data.vertices))

def material(name,color,roughness):
    mat=bpy.data.materials.new(name); mat.use_nodes=True
    image=bpy.data.images.new(name+'_Color',width=4,height=4)
    image.pixels[:]=[component for i in range(16) for component in (color[0]*(.9+.1*(i%3)/2),color[1]*(.9+.1*(i%3)/2),color[2]*(.9+.1*(i%3)/2),1)]
    image.pack()
    shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
    mat.node_tree.links.new(tex.outputs['Color'],shader.inputs['Base Color'])
    shader.inputs['Roughness'].default_value=roughness
    return mat
tooth=material('Raker018_InternalTeeth',(.30,.26,.19),.5)
parts=[]
for lower in [False,True]:
    vertices=[]; faces=[]
    for i in range(9):
        x=(i-4)*.0085+(.003 if lower else 0)
        y=(-.152 if lower else -.174)+.028*(x/.040)**2
        base=1.995 if lower else 2.027
        length=.014 if lower else .017+(.002 if i in [1,7] else 0)
        tip=base+length if lower else base-length
        offset=len(vertices)
        for level in range(3):
            z=base+(tip-base)*[0,.72,1][level]
            radius=.0029*[1,.65,.25][level]
            for j in range(8):
                angle=math.tau*j/8
                vertices.append((x+math.cos(angle)*radius,y+math.sin(angle)*radius*.8,z))
        faces.append(tuple(offset+j for j in reversed(range(8))))
        for level in range(2):
            for j in range(8):
                a=offset+level*8+j;b=offset+level*8+(j+1)%8
                faces.append((a,b,b+8,a+8))
        faces.append(tuple(offset+16+j for j in range(8)))
    data=bpy.data.meshes.new('InternalDentalArch');data.from_pydata(vertices,[],faces);data.update()
    ob=bpy.data.objects.new('LowerInternalTeeth' if lower else 'UpperInternalTeeth',data);scene.collection.objects.link(ob)
    data.materials.append(tooth);data.uv_layers.new(name='UVMap')
    group=ob.vertex_groups.new(name='jaw' if lower else 'head');group.add(list(range(len(vertices))),1,'REPLACE')
    for p in data.polygons:p.use_smooth=True
    parts.append(ob)
for ob in scene.objects:ob.select_set(False)
mesh.select_set(True)
for ob in parts:ob.select_set(True)
bpy.context.view_layer.objects.active=mesh;bpy.ops.object.join()
bm=bmesh.new();bm.from_mesh(mesh.data)
bmesh.ops.recalc_face_normals(bm,faces=[f for f in bm.faces if f.material_index==3])
bm.to_mesh(mesh.data);bm.free();mesh.data.update()
# Replace the jaw curves on private copied actions. Closed hold, anticipation,
# a brief open pause, then one fast closure exactly at the .38 s damage frame.
def smooth(t):
    t=max(0,min(1,t));return t*t*(3-2*t)
rig.data.pose_position='POSE'
for track in rig.animation_data.nla_tracks:
    action=track.strips[0].action
    rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
    for frame in range(int(action.frame_range[1])+1):
        seconds=frame/60
        angle=0
        if track.name.endswith('_bite'):
            opening=smooth((seconds-.045)/.175)*(1-smooth((seconds-.285)/.095))
            angle=27*opening+2.5*math.sin(math.pi*max(0,min(1,(seconds-.40)/.13))) if seconds<.53 else 0
        bone=rig.pose.bones['jaw']
        axis=bone.bone.matrix_local.to_3x3().inverted()@Vector((1,0,0))
        bone.rotation_quaternion=Quaternion(axis,math.radians(angle))
        bone.keyframe_insert(data_path='rotation_quaternion',frame=frame)
scene['revision']='v018 native sealed mouth, internal teeth, eased 27-degree jaw'
scene.render.engine='BLENDER_EEVEE'
scene.render.image_settings.file_format='PNG'
scene.render.resolution_x=800;scene.render.resolution_y=800;scene.render.resolution_percentage=100
for name,frame in [('closed',0),('open',14)]:
    action=next(t.strips[0].action for t in rig.animation_data.nla_tracks if t.name=='grab_stand_bite')
    rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0];scene.frame_set(frame)
    bpy.context.view_layer.update()
    pose=rig.pose.bones['head'].matrix@rig.data.bones['head'].matrix_local.inverted()
    focus=pose@Vector((0,-.08,2.04))
    scene.camera.location=focus+pose.to_3x3()@Vector((.08,-1,.035))
    scene.camera.rotation_euler=(focus-scene.camera.location).to_track_quat('-Z','Y').to_euler()
    scene.camera.data.ortho_scale=.34
    scene.render.filepath=OUT+'mouth_'+name+'.png';bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT+'monster_refined_v018.blend')
mesh.data.calc_loop_triangles()
print('V018_METRICS',len(mesh.data.vertices),len(mesh.data.loop_triangles),len(mesh.data.materials))
