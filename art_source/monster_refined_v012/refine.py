"""Refine the actual head / trunk surface, preserving v011 expressions and rig.
Run in Blender with v011 loaded. Earlier revisions are not modified.
"""
import bpy
import bmesh
import math
import json
from mathutils import Vector
OUT='C:/Users/evan4/Projects/ApocalypseRV/art_source/monster_refined_v012/'
source=bpy.data.scenes['MONSTER_REFINED_V011']
old=bpy.data.scenes.get('MONSTER_REFINED_V012')
if old:
    assert old.get('revision_owner')=='raker_v012_refine'
    bpy.context.window.scene=source
    for ob in list(old.objects): bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.scenes.remove(old)
scene=bpy.data.scenes.new('MONSTER_REFINED_V012')
scene['revision_owner']='raker_v012_refine'
bpy.context.window.scene=scene
scene.render.fps=30
rig=bpy.data.objects['Refined011_Rig'].copy()
rig.data=rig.data.copy()
rig.name='Refined012_Rig'
scene.collection.objects.link(rig)
mesh=bpy.data.objects['Refined011_Mesh'].copy()
mesh.data=mesh.data.copy()
mesh.name='Refined012_Mesh'
mesh.parent=rig
scene.collection.objects.link(mesh)
for mod in mesh.modifiers:
    if mod.type=='ARMATURE': mod.object=rig
for track in rig.animation_data.nla_tracks: track.mute=True
rig.animation_data.action=bpy.data.actions['raker_idle']
rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(0)

# Keep shoulder/hip articulation topology. New vertices interpolate UVs and
# deform weights; geometry smoothing is faded out before these boundaries.
protected={g.index for g in mesh.vertex_groups if any(n in g.name for n in ['arm_','clavicle_','thigh_','shin_','hand_','foot_','toe_'])}
eligible={v.index for v in mesh.data.vertices if v.co.z>1.12 and not any(g.group in protected and g.weight>.001 for g in v.groups)}
bm=bmesh.new();bm.from_mesh(mesh.data)
bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if all(v.index in eligible for v in f.verts)])
bmesh.ops.subdivide_edges(bm,edges=[e for e in bm.edges if all(v.index in eligible for v in e.verts)],cuts=1,use_grid_fill=True)
bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if len(f.verts)>3 and all(v.co.z>1.12 and abs(v.co.x)<.20 for v in f.verts)])
bm.to_mesh(mesh.data);bm.free()

def gauss(x,c,w): return math.exp(-((x-c)/w)**2)
def clamp(x): return max(0,min(1,x))
neighbors=[set() for v in mesh.data.vertices]
for edge in mesh.data.edges:
    a,b=edge.vertices
    neighbors[a].add(b);neighbors[b].add(a)
orig=[v.co.copy() for v in mesh.data.vertices]
amount=[]
for v in mesh.data.vertices:
    x,y,z=v.co
    w={mesh.vertex_groups[g.group].name:g.weight for g in v.groups}
    joint=sum(g.weight for g in v.groups if g.group in protected)
    head=w.get('head',0)
    torso=sum(w.get(n,0) for n in ['pelvis','spine_01','spine_02','spine_03','hump','neck_01','neck_02'])
    strength=.45*clamp((z-1.12)/.12)*torso*max(0,1-joint*10)
    if head>.9:
        eye=gauss(abs(x),.044,.045)*gauss(z,2.076,.045)*gauss(y,-.17,.08)
        mouth=gauss(x,0,.065)*gauss(z,2.016,.024)*gauss(y,-.17,.08)
        strength=.48*(1-.80*max(eye,mouth))
    amount.append(strength)

# Uniform relaxation changes actual silhouettes, not just triangle counts.
# Freeze joint transition vertices so the already validated bends remain stable.
for iteration in range(10):
    coords=[v.co.copy() for v in mesh.data.vertices]
    for v in mesh.data.vertices:
        if amount[v.index]<=0 or not neighbors[v.index]: continue
        average=sum((coords[i] for i in neighbors[v.index]),Vector())/len(neighbors[v.index])
        v.co=coords[v.index].lerp(average,amount[v.index])

# Restore 2.18 m by a smooth adjustment of the crown only (not a rig rescale).
top=max(v.co.z for v in mesh.data.vertices)
delta=2.18-top
for v in mesh.data.vertices:
    if v.co.z>2.105:
        v.co.z+=delta*clamp((v.co.z-2.105)/(top-2.105))
for p in mesh.data.polygons: p.use_smooth=True
mesh.data.update();mesh.data.calc_loop_triangles()
scene['refinement_stats']=json.dumps({'previous_vertices':2966,'previous_triangles':5928,
    'vertices':len(mesh.data.vertices),'triangles':len(mesh.data.loop_triangles),
    'max_surface_adjustment_m':max((v.co-orig[v.index]).length for v in mesh.data.vertices),
    'height_m':max(v.co.z for v in mesh.data.vertices)-min(v.co.z for v in mesh.data.vertices)})

for ob in source.objects:
    if ob.name.startswith('Review011_'):
        c=ob.copy();c.data=ob.data.copy();c.name=ob.name.replace('011','012');scene.collection.objects.link(c)
        if c.type=='CAMERA':scene.camera=c
scene.world=source.world.copy()
try:scene.render.engine='BLENDER_EEVEE'
except TypeError:pass
scene.render.resolution_x=900;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
for label,location,target,scale in [('head',(1.6,-5,2.28),(0,-.04,2.045),.40),('threequarter',(3,-6,2.65),(0,0,1.10),2.65)]:
    scene.camera.location=location
    scene.camera.rotation_euler=(Vector(target)-scene.camera.location).to_track_quat('-Z','Y').to_euler()
    scene.camera.data.ortho_scale=scale
    scene.render.filepath=OUT+label+'.png'
    bpy.ops.render.render(write_still=True)
for ob in scene.objects:ob.select_set(False)
mesh.select_set(True);bpy.context.view_layer.objects.active=mesh
bpy.ops.wm.save_as_mainfile(filepath=OUT+'monster_refined_v012.blend')
print(scene['refinement_stats'])
