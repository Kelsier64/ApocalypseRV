"""Prepend waterproof_fields.py. Bake only the dyeable suit, preserving fixed atlas."""
import bpy,math,json
from mathutils import Vector,Matrix,noise
from array import array
OUT='C:/Users/evan4/Projects/ApocalypseRV/art_source/player_masked_survivor/work/texture-bake/'
scene=bpy.data.scenes['PLAYER_MASKED_SURVIVOR'];bpy.context.window.scene=scene;torso=bpy.data.objects['body_torso'];rig=bpy.data.objects['Survivor_Rig'];rig.animation_data.action=None
for tr in rig.animation_data.nla_tracks:tr.mute=True
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
def clamp(v,a=0,b=1):return max(a,min(b,v))
def height_only(p,panel):return waterproof_height(p)*(.13 if panel else 1)
def detail(p,category,panel):
    broad=noise.noise(p*23);grain=noise.noise(p*320)
    scuff=max(0,noise.noise(p*57)-.18)
    value=clamp(.78+.009*broad+.004*grain+.035*scuff,.72,.85)
    rough=clamp(.52+.045*broad+.15*scuff,.44,.68)
    return (value,value,value),rough,height_only(p,panel)
def bake(matname,prefix):
    SIZE=1024
    base=array('f',[.75,.75,.75,1])* (SIZE*SIZE)
    rough=array('f',[.85,.85,.85,1])* (SIZE*SIZE)
    normal=array('f',[.5,.5,1,1])* (SIZE*SIZE)
    occupied=bytearray(SIZE*SIZE)
    count=0
    for ob in scene.objects:
        if ob.type!='MESH' or ob.get('exclude_from_export',False):continue
        me=ob.data;me.calc_loop_triangles();me.calc_tangents(uvmap=me.uv_layers.active.name)
        uv=me.uv_layers.active.data
        for tri in me.loop_triangles:
            poly=me.polygons[tri.polygon_index]
            if me.materials[poly.material_index].name!=matname:continue
            loops=list(tri.loops)
            tex=[uv[i].uv.copy()*SIZE for i in loops]
            points=[ob.matrix_world@me.vertices[me.loops[i].vertex_index].co for i in loops]
            category='cloth'
            if matname=='equipment_atlas':
                v=sum(uv[i].uv.y for i in loops)/3
                category='black' if v<.455 else 'hood' if v<.705 else 'silver' if v<.835 else 'bone'
            panel=[]
            if ob==torso and 512<=min(poly.vertices) and max(poly.vertices)<584:
                start=512+((min(poly.vertices)-512)//8)*8
                vs=[me.vertices[start+i].co.copy() for i in range(4)]
                panel=[(vs[i],vs[(i+1)%4]) for i in range(4)]
            a,b,c=tex;den=(b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y)
            if abs(den)<1e-8:continue
            xmin=max(0,int(min(p.x for p in tex)));xmax=min(SIZE-1,math.ceil(max(p.x for p in tex)))
            ymin=max(0,int(min(p.y for p in tex)));ymax=min(SIZE-1,math.ceil(max(p.y for p in tex)))
            tangents=[me.loops[i].tangent.copy() for i in loops]
            normals=[me.corner_normals[i].vector.copy() for i in loops]
            handed=me.loops[loops[0]].bitangent_sign
            for yy in range(ymin,ymax+1):
                for xx in range(xmin,xmax+1):
                    px=xx+.5;py=yy+.5
                    u=((b.y-c.y)*(px-c.x)+(c.x-b.x)*(py-c.y))/den
                    v=((c.y-a.y)*(px-c.x)+(a.x-c.x)*(py-c.y))/den;w=1-u-v
                    if min(u,v,w)<-1e-6:continue
                    p=points[0]*u+points[1]*v+points[2]*w
                    color,r,h=detail(p,category,panel)
                    t=(tangents[0]*u+tangents[1]*v+tangents[2]*w).normalized()
                    n=(normals[0]*u+normals[1]*v+normals[2]*w).normalized()
                    bit=n.cross(t).normalized()*handed
                    eps=.0005
                    du=(height_only(p+t*eps,panel)-height_only(p-t*eps,panel))/(2*eps)
                    dv=(height_only(p+bit*eps,panel)-height_only(p-bit*eps,panel))/(2*eps)
                    nn=Vector((-du,-dv,1)).normalized()
                    idx=yy*SIZE+xx;j=idx*4
                    base[j:j+4]=array('f',(*color,1));rough[j:j+4]=array('f',(r,r,r,1))
                    normal[j:j+4]=array('f',(nn.x*.5+.5,nn.y*.5+.5,nn.z*.5+.5,1))
                    occupied[idx]=1;count+=1
    # Six texel gutters, preserving UV islands and fixed-color atlas bands.
    for step in range(6):
        add=[]
        for idx in range(SIZE*SIZE):
            if occupied[idx]:continue
            x=idx%SIZE;y=idx//SIZE
            for off in [-1,1,-SIZE,SIZE]:
                k=idx+off
                if k<0 or k>=SIZE*SIZE or (off==-1 and x==0) or (off==1 and x==SIZE-1):continue
                if occupied[k]:add.append((idx,k));break
        for idx,k in add:
            occupied[idx]=1
            for pixels in [base,rough,normal]:pixels[idx*4:idx*4+4]=pixels[k*4:k*4+4]
    images=[]
    for suffix,pixels,data in [('basecolor',base,False),('roughness',rough,True),('normal',normal,True)]:
        name=('cloth_neutral' if prefix=='cloth' and suffix=='basecolor' else prefix)+'_'+suffix+'_'+str(SIZE)
        name='waterproof_'+name
        previous=bpy.data.images.get(name)
        if previous:previous.name='ARCHIVE_'+name
        im=bpy.data.images.new(name,width=SIZE,height=SIZE,alpha=False)
        if data:im.colorspace_settings.name='Non-Color'
        im.pixels.foreach_set(pixels);im.filepath_raw=OUT+name+'.png';im.file_format='PNG';im.save();im.pack()
        images.append(im)
    mat=bpy.data.materials[matname];nodes=mat.node_tree.nodes;links=mat.node_tree.links
    shader=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
    if matname=='suit_dye' and 'Specular IOR Level' in shader.inputs:
        shader.inputs['Specular IOR Level'].default_value=.5
    base_node=next(n for n in nodes if n.type=='TEX_IMAGE' and 'basecolor' in n.image.name)
    base_node.image=images[0]
    for n in list(nodes):
        if n.type in ['NORMAL_MAP'] or (n.type=='TEX_IMAGE' and n!=base_node):nodes.remove(n)
    rt=nodes.new('ShaderNodeTexImage');rt.image=images[1];rt.label='Baked fabric roughness'
    links.new(rt.outputs['Color'],shader.inputs['Roughness'])
    nt=nodes.new('ShaderNodeTexImage');nt.image=images[2];nt.label='Baked OpenGL tangent fabric / stitching'
    nm=nodes.new('ShaderNodeNormalMap');nm.space='TANGENT';nm.inputs['Strength'].default_value=1
    links.new(nt.outputs['Color'],nm.inputs['Color']);links.new(nm.outputs['Normal'],shader.inputs['Normal'])
    shader.inputs['Roughness'].default_value=.52
    shader.inputs['Metallic'].default_value=0
    shader.inputs['Coat Weight'].default_value=0
    mat['fabric_revision']=10;mat['texture_authoring']='PU-coated waterproof workwear; satin reflection, crease normals, neutral dye; no lighting baked'
    print('BAKED',matname,count,'texels',[(im.name,list(im.size)) for im in images])

bake('suit_dye','cloth')
scene['fabric_material_notes']='PU-coated waterproof workwear: 1k neutral albedo, satin roughness, dense directional creases; fixed atlas unchanged'
print('Waterproof material baked')
