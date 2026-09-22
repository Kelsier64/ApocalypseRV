"""Blender MCP: v010 -> v011. Deeper eye sockets, sculpted mouth, dirty skin.
Only rebuilds this script's v011 scene. Retains earlier revisions and actions.
"""
import bpy
import bmesh
import math
from mathutils import Vector, noise
OUT='C:/Users/evan4/Projects/ApocalypseRV/art_source/monster_refined_v011/'
old=bpy.data.scenes.get('MONSTER_REFINED_V011')
if old:
    assert old.get('revision_owner')=='raker_v011_refine'
    bpy.context.window.scene=bpy.data.scenes['MONSTER_REFINED_V010']
    for ob in list(old.objects): bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.scenes.remove(old)
scene=bpy.data.scenes.new('MONSTER_REFINED_V011')
scene['revision_owner']='raker_v011_refine'
bpy.context.window.scene=scene
scene.render.fps=30
rig=bpy.data.objects['Refined010_Rig'].copy()
rig.data=rig.data.copy()
rig.name='Refined011_Rig'
scene.collection.objects.link(rig)
mesh=bpy.data.objects['Refined010_Mesh'].copy()
mesh.data=mesh.data.copy()
mesh.name='Refined011_Mesh'
mesh.parent=rig
scene.collection.objects.link(mesh)
for mod in mesh.modifiers:
    if mod.type=='ARMATURE': mod.object=rig
for track in rig.animation_data.nla_tracks: track.mute=True
rig.animation_data.action=bpy.data.actions['raker_idle']
rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(0)

bm=bmesh.new()
bm.from_mesh(mesh.data)
region={v.index for v in bm.verts if v.co.y<-.150 and 1.982<v.co.z<2.047 and abs(v.co.x)<.068}
bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if all(v.index in region for v in f.verts)])
bmesh.ops.subdivide_edges(bm,edges=[e for e in bm.edges if all(v.index in region for v in e.verts)],cuts=2,use_grid_fill=True)
bm.to_mesh(mesh.data)
bm.free()

def gauss(x,c,w): return math.exp(-((x-c)/w)**2)
def clamp(x): return max(0,min(1,x))
original=[v.co.copy() for v in mesh.data.vertices]
for v in mesh.data.vertices:
    x,y,z=v.co
    if y<-.13 and z>1.98:
        cx=.042 if x>=0 else -.042
        radius=((x-cx)/.031)**2+((z-2.076)/.027)**2
        orbit=math.exp(-radius*1.7)*gauss(y,-.184,.055)
        v.co.y+=.034*orbit
        expansion=.26*math.exp(-radius*1.3)
        v.co.x+=(x-cx)*expansion
        v.co.z+=(z-2.076)*expansion
        # A closed, continuous cavity with a recessed dark back; no black decal.
        mouth_z=2.014+.004*(abs(x)/.040)**2+.0015*math.sin(x*130)
        width=math.exp(-(x/.043)**6)
        dz=z-mouth_z
        opening=width*math.exp(-(dz/.0065)**4)
        lip=width*gauss(abs(dz),.010,.0035)
        v.co.y+=.031*opening-.004*lip
mesh.data.update()

# Resolve non-planar transition ngons at the edge of the mouth subdivision.
bm=bmesh.new();bm.from_mesh(mesh.data)
bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if len(f.verts)>3 and all(v.co.z>1.97 for v in f.verts)])
bm.to_mesh(mesh.data);bm.free();mesh.data.update()

colors=mesh.data.color_attributes.get('RakerSkin')
for v in mesh.data.vertices:
    x,y,z=original[v.index]
    w={mesh.vertex_groups[g.group].name:g.weight for g in v.groups}
    n=noise.noise(Vector((x*8+7,y*8-3,z*8)))
    m=noise.noise(Vector((x*35,y*35,z*35+2)))
    soil=clamp(.42+n*.9+m*.18)
    # Persistent anatomical grime, in addition to uneven mud patches.
    crevice=.48*gauss(z,1.91,.06)
    crevice+=.48*gauss(abs(x),.19,.055)*gauss(z,1.64,.09)
    crevice+=.25*gauss(x,0,.045)*gauss(z,1.45,.25)
    crevice+=.40*gauss(z,.08,.10)
    for name,weight in w.items():
        if any(p in name for p in ['hand_','index_','middle_','ring_','pinky_','thumb_']):
            crevice+=.25*weight
    grime=clamp(soil*.60+crevice)
    clean=(.34,.32,.275)
    dirt=(.035,.028,.019)
    rgb=[clean[i]*(1-grime)+dirt[i]*grime for i in range(3)]
    if y<-.12 and z>1.98:
        eye=gauss(abs(x),.042,.030)*gauss(z,2.076,.028)
        stain=gauss(abs(x),.042,.020)*gauss(z,2.036,.052)
        for i in range(3): rgb[i]*=1-clamp(.83*eye+.38*stain)
        mouth_z=2.014+.004*(abs(x)/.040)**2+.0015*math.sin(x*130)
        width=math.exp(-(x/.045)**6)
        lip=width*gauss(z,mouth_z,.014)
        cavity=width*math.exp(-((z-mouth_z)/.0062)**4)
        for i in range(3):
            rgb[i]=rgb[i]*(1-.82*lip)+(.045,.020,.014)[i]*.82*lip
            rgb[i]=rgb[i]*(1-cavity)+(.004,.003,.002)[i]*cavity
    colors.data[v.index].color=(*rgb,1)
mesh.data.color_attributes.active_color=colors

skin=bpy.data.materials.new('Raker011_GrimeSkin')
skin.use_nodes=True
nodes=skin.node_tree.nodes
links=skin.node_tree.links
bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
bsdf.inputs['Roughness'].default_value=.96
vc=nodes.new('ShaderNodeVertexColor');vc.layer_name='RakerSkin'
coord=nodes.new('ShaderNodeTexCoord')
tex=nodes.new('ShaderNodeTexNoise');tex.noise_dimensions='3D';tex.noise_type='FBM'
tex.inputs['Scale'].default_value=29;tex.inputs['Detail'].default_value=4;tex.inputs['Roughness'].default_value=.78
links.new(coord.outputs['Object'],tex.inputs['Vector'])
ramp=nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position=.29;ramp.color_ramp.elements[0].color=(.09,.075,.045,1)
ramp.color_ramp.elements[1].position=.67;ramp.color_ramp.elements[1].color=(1.12,1.08,.95,1)
mix=nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs['Fac'].default_value=.85
links.new(tex.outputs['Fac'],ramp.inputs['Fac']);links.new(ramp.outputs['Color'],mix.inputs['Color2'])
links.new(vc.outputs['Color'],mix.inputs['Color1']);links.new(mix.outputs['Color'],bsdf.inputs['Base Color'])
eyes=bpy.data.materials.new('Raker011_EyeDepth');eyes.use_nodes=True
eb=next(n for n in eyes.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
eb.inputs['Base Color'].default_value=(.002,.0015,.001,1);eb.inputs['Roughness'].default_value=1
indices=[p.material_index for p in mesh.data.polygons]
mesh.data.materials.clear();mesh.data.materials.append(skin);mesh.data.materials.append(eyes)
for p,i in zip(mesh.data.polygons,indices):p.material_index=i

source=bpy.data.scenes['MONSTER_REFINED_V010']
for ob in source.objects:
    if ob.name.startswith('Review010_'):
        c=ob.copy();c.data=ob.data.copy();c.name=ob.name.replace('010','011');scene.collection.objects.link(c)
        if c.type=='CAMERA':scene.camera=c
scene.world=source.world.copy()
try:scene.render.engine='BLENDER_EEVEE'
except TypeError:pass
scene.render.resolution_x=900;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.camera.location=(1.6,-5,2.28)
scene.camera.rotation_euler=(Vector((0,-.04,2.045))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.camera.data.ortho_scale=.40
scene.render.filepath=OUT+'head_work.png'
for ob in scene.objects:ob.select_set(False)
mesh.select_set(True);bpy.context.view_layer.objects.active=mesh
bpy.ops.wm.save_as_mainfile(filepath=OUT+'monster_refined_v011.blend')
bpy.ops.render.render(write_still=True)
print('V011_SCULPT_COMPLETE',len(mesh.data.vertices))
