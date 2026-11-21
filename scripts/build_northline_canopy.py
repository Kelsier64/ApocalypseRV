"""Build the Northline folded-plate canopy with Blender --background --python."""
from pathlib import Path
import bpy
import bmesh


OUTPUT = Path(__file__).resolve().parents[1] / "assets/models/gas_station/northline_canopy.glb"
palette = {
    "Oxide enamel": "a94730", "Sun stripe": "dda553", "Ivory return": "d4c9a9",
    "Petrol steel": "315653", "Galvanized roof": "858b80", "Panel seam": "64746e",
    "Safety mustard": "c39a4d", "Lamp glass": "f2dfb0",
}
vertices, faces, face_materials = [], [], []


def solid(lower, upper, material):
    """Join matching perimeter loops, specified in Godot's local metres."""
    start, count = len(vertices), len(lower)
    vertices.extend((x, -z, y) for x, y, z in lower + upper)
    polygons = [list(reversed(range(count))), list(range(count, 2 * count))]
    for i in range(count):
        j = (i + 1) % count
        polygons.append([i, j, count + j, count + i])
    for polygon in polygons:
        faces.append([start + n for n in polygon])
        face_materials.append(list(palette).index(material))


def block(x, y, z, w, h, d, material):
    bottom = [(x+i*w/2, y-h/2, z+j*d/2) for i,j in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    solid(bottom, [(a,b+h,c) for a,b,c in bottom], material)


def underside(x):
    return 5.45 + .175*x


def eave(x):
    return 5.12 + .155*x


def sheet(side, plan, height, thickness, material):
    lower = [(side*x, underside(x)+height, z) for x,z in plan]
    solid(lower, [(x,y+thickness,z) for x,y,z in lower], material)


def web(side, z, profile, width, material):
    solid([(side*x,y,z-width/2) for x,y in profile],
          [(side*x,y,z+width/2) for x,y in profile], material)


def wing(side):
    tip = 10.4
    plan = [(0,-eave(0)), (tip,-eave(tip)), (tip,eave(tip)), (0,eave(0))]
    sheet(side, plan, 0, .19, "Ivory return")
    sheet(side, plan, .19, .09, "Galvanized roof")
    for edge in (-1,1):
        lip = [(0,edge*(eave(0)-.12)), (tip,edge*(eave(tip)-.12)),
               (tip,edge*eave(tip)), (0,edge*eave(0))]
        for offset,depth,mat in [(-.24,.075,"Petrol steel"),(-.165,.095,"Sun stripe"),
                                 (-.07,.30,"Oxide enamel"),(.23,.075,"Ivory return")]:
            sheet(side, lip, offset, depth, mat)
        # The folded sheet turns back at the corner in three ivory flashes.
        for i in range(3):
            a = 8.7 + i*.46
            ribbon = [(a, underside(a)-.065,edge*(eave(a)+.005)),
                      (a+.18,underside(a+.18)-.065,edge*(eave(a+.18)+.005)),
                      (a+.38,underside(a+.38)+.22,edge*(eave(a+.38)+.005)),
                      (a+.20,underside(a+.20)+.22,edge*(eave(a+.20)+.005))]
            ribbon = [(side*x,y,z) for x,y,z in ribbon]
            solid(ribbon, [(x,y,z+edge*.009) for x,y,z in ribbon], "Ivory return")
    end = [(tip-.10,-eave(tip)),(tip,-eave(tip)),(tip,eave(tip)),(tip-.10,eave(tip))]
    sheet(side,end,-.16,.39,"Oxide enamel")
    for j in range(1,11):
        x = j*.93
        strip = [(x,-eave(x)+.08),(x+.055,-eave(x)+.08),
                 (x+.055,eave(x)-.08),(x,eave(x)-.08)]
        sheet(side,strip,.28,.045,"Panel seam")
    for z in (-3.5,3.5):
        block(side*6,2.31,z,.32,4.34,.34,"Petrol steel")
        block(side*6,.55,z,.43,.82,.45,"Ivory return")
        block(side*6,.96,z,.44,.13,.46,"Safety mustard")
        web(side,z,[(5.84,4.0),(6.15,4.47),(3.58,underside(3.58)),
                    (3.05,underside(3.05))],.26,"Petrol steel")
        web(side,z,[(5.85,4.45),(6.16,4.0),(8.98,underside(8.98)),
                    (8.38,underside(8.38))],.26,"Petrol steel")
        web(side,z,[(1.3,underside(1.3)),(9.95,underside(9.95)),
                    (9.95,underside(9.95)-.12),(5.9,underside(5.9)-.38),
                    (1.3,underside(1.3)-.10)],.24,"Panel seam")
    for x in (3.15,8.85):
        block(side*x,underside(x)-.10,0,.30,.16,2.15,"Petrol steel")
        block(side*x,underside(x)-.195,0,.23,.04,2.03,"Lamp glass")


def linear(channel):
    value = int(channel,16)/255
    return ((value+.055)/1.055)**2.4 if value>.04045 else value/12.92


bpy.ops.wm.read_factory_settings(use_empty=True)
for direction in (-1,1):
    wing(direction)
mesh = bpy.data.meshes.new("Folded sheet and steelwork")
mesh.from_pydata(vertices, [], faces)
obj = bpy.data.objects.new("Northline canopy",mesh)
bpy.context.collection.objects.link(obj)
for name, color in palette.items():
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    rgba = tuple(linear(color[i:i+2]) for i in (0,2,4)) + (1,)
    shader.inputs["Base Color"].default_value = rgba
    shader.inputs["Roughness"].default_value = .72
    shader.inputs["Metallic"].default_value = .23 if name != "Lamp glass" else 0
    if name == "Lamp glass":
        shader.inputs["Emission Color"].default_value = rgba
        shader.inputs["Emission Strength"].default_value = .65
    mesh.materials.append(mat)
for polygon, material_index in zip(mesh.polygons,face_materials):
    polygon.material_index = material_index
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
bm.to_mesh(mesh)
bm.free()
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", export_yup=True)
