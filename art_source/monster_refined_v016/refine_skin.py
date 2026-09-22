import bpy
mesh=bpy.data.objects['Refined016_Mesh']
source=bpy.data.objects['Refined015_Mesh']
weights=[{g.group:g.weight for g in v.groups} for v in source.data.vertices]
neighbors=[set() for v in mesh.data.vertices]
for edge in mesh.data.edges:
    a,b=edge.vertices
    neighbors[a].add(b)
    neighbors[b].add(a)
region=[v.index for v in mesh.data.vertices if .105<abs(v.co.x)<.36 and 1.52<v.co.z<1.84]
for iteration in range(10):
    previous=[dict(w) for w in weights]
    for index in region:
        blend={}
        for neighbor in neighbors[index]:
            for group,value in previous[neighbor].items():
                blend[group]=blend.get(group,0)+value/len(neighbors[index])
        for group,value in previous[index].items(): blend[group]=blend.get(group,0)*.65+value*.35
        total=sum(blend.values())
        weights[index]={group:value/total for group,value in blend.items() if value>.00001}
for index in region:
    for group in list(mesh.data.vertices[index].groups): mesh.vertex_groups[group.group].remove([index])
    for group,value in weights[index].items(): mesh.vertex_groups[group].add([index],value,'REPLACE')
print('Smoothed shoulder transition weights',len(region))
def weight_value(pair):
    return pair[1]
for vertex in mesh.data.vertices:
    influences=[(g.group,g.weight) for g in vertex.groups if g.weight>0]
    if len(influences)>4:
        selected=sorted(influences,key=weight_value,reverse=True)[:4]
        total=sum(value for group,value in selected)
        for group in list(vertex.groups): mesh.vertex_groups[group.group].remove([vertex.index])
        for group,value in selected: mesh.vertex_groups[group].add([vertex.index],value/total,'REPLACE')
# Dedicated dark wet oral lining follows the articulated bowl and lower lip.
material=bpy.data.materials.get('Raker016_OralLining')
if material is None:
    material=bpy.data.materials.new('Raker016_OralLining')
    material.use_nodes=True
    image=bpy.data.images.new('Raker016_MouthColor',width=2,height=2)
    image.generated_color=(.018,.005,.004,1)
    image.pack()
    shader=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    texture=material.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image=image
    material.node_tree.links.new(texture.outputs['Color'],shader.inputs['Base Color'])
    shader.inputs['Roughness'].default_value=.58
if material.name not in mesh.data.materials: mesh.data.materials.append(material)
slot=mesh.data.materials.find(material.name)
count=0
for polygon in mesh.data.polygons:
    center=polygon.center
    if abs(center.x)<.044 and center.y<-.13 and 2.007<center.z<2.019:
        polygon.material_index=slot
        count+=1
print('Oral lining faces',count)
