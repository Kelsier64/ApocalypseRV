"""Build the portable receiver and export the game model. Run in Blender background mode."""

from math import cos, pi, sin
from pathlib import Path
from random import Random

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/models/shortwave_radio/shortwave_radio.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb, roughness, metal=0, weather=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metal
    if weather is not None:
        image = wear_texture(name, weather)
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        mat.node_tree.links.new(node.outputs["Color"], shader.inputs["Base Color"])
    return mat


def wear_texture(name, palette):
    paint, grime, bare, seed = palette
    rng = Random(seed)
    size = 128
    tiles = [rng.uniform(-1, 1) for _ in range(64)]
    scuffs = []
    for _ in range(72):
        side = rng.randrange(4)
        along = rng.randrange(4, size - 4)
        inset = rng.choice([1, 2, 3, 5, 7, 10, 12])
        x, y = [(along, inset), (along, size - inset), (inset, along), (size - inset, along)][side]
        scuffs.append((x, y, rng.randrange(1, 6), rng.randrange(1, 4)))
    chips = {(x + i, y + j) for x, y, w, h in scuffs for i in range(w) for j in range(h)
             if rng.random() > .26}
    pixels = []
    for y in range(size):
        for x in range(size):
            edge = min(x, y, size - 1 - x, size - 1 - y)
            broad = tiles[(y // 16) * 8 + x // 16]
            stains = sin(x * .072 + cos(y * .09)) + sin((y + x) * .045)
            dirt = max(0, .34 * stains + .37 * (1 - min(edge, 14) / 14) + .13 * broad)
            pigment = bare if (x, y) in chips else tuple(a + (b - a) * dirt for a, b in zip(paint, grime))
            variation = rng.uniform(-.024, .024) + broad * .017
            pixels.extend((*[max(0, min(1, channel + variation)) for channel in pigment], 1))
    image = bpy.data.images.new(name + "_albedo", size, size, alpha=False)
    image.pixels.foreach_set(pixels)
    image.pack()
    return image


shell = material("Olive baked enamel", (.25, .27, .19), .91, .16,
                 ((.37, .40, .31), (.15, .17, .12), (.49, .43, .33), 47))
panel = material("Charcoal faceplate", (.22, .23, .20), .87, .05,
                 ((.25, .27, .24), (.12, .14, .12), (.40, .38, .33), 99))
cream = material("Yellowed scale backing", (.58, .54, .40), .79, 0,
                 ((.65, .60, .46), (.35, .31, .21), (.74, .70, .59), 33))
rubber = material("Black rubber", (.043, .047, .039), .95)
deep = material("Recess and port interiors", (.012, .017, .017), .94)
steel = material("Dulled zinc and antenna steel", (.35, .37, .35), .59, .46)
dark_steel = material("Oxidized speaker grille", (.13, .144, .13), .83, .28)
red = material("Oxide red dial needle", (.41, .103, .044), .79)
ink = material("Scale ink", (.06, .049, .036), .85)
tape = material("Old fabric repair tape", (.26, .22, .155), .97)


def sized_uvs(obj, dims):
    uv_layer = obj.data.uv_layers.active.data
    for poly in obj.data.polygons:
        axis = max(range(3), key=lambda a: abs(poly.normal[a]))
        u, v = [(1, 2), (0, 2), (0, 1)][axis]
        for loop in poly.loop_indices:
            point = obj.data.vertices[obj.data.loops[loop].vertex_index].co
            uv_layer[loop].uv = (point[u] / dims[u] + .5, point[v] / dims[v] + .5)


def box(name, point, dims, mat, bevel=0, roll=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=point)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler.y = roll
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Stamped edge", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    sized_uvs(obj, dims)
    return obj


def cylinder(name, start, end, radius, mat, sides=12):
    a, b = Vector(start), Vector(end)
    axis = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=axis.length,
                                      location=(a + b) / 2)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = axis.to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(mat)
    return obj


def screw(x, y, z, back=False):
    direction = 1 if back else -1
    cylinder("Recessed screw socket", (x, y, z), (x, y + direction * .0007, z), .0034, deep, 8)
    cylinder("Slotted zinc screw", (x, y, z), (x, y + direction * .001, z), .00255, steel, 8)
    box("Screw slot", (x, y + direction * .0011, z), (.0033, .0002, .00053), deep,
        roll=.9 * sin(x * 38 + z * 46))


def stencil(text, x, z, size, mat, y=-.0531):
    curve = bpy.data.curves.new(text, "FONT")
    curve.body = text
    curve.size = size
    curve.resolution_u = 2
    curve.materials.append(mat)
    obj = bpy.data.objects.new(text, curve)
    bpy.context.collection.objects.link(obj)
    obj.location = (x, y, z)
    obj.rotation_euler.x = pi / 2
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")


# The radio stands on four rubber feet. Its top handle clears the steel case.
box("Pressed steel case", (0, .004, -.012), (.278, .094, .133), shell, .011)
box("Face gasket", (0, -.043, -.012), (.267, .014, .121), rubber, .007)
box("Inset instrument face", (0, -.048, -.012), (.255, .009, .112), panel, .006)
box("Rear housing seam", (0, .037, -.013), (.274, .003, .128), rubber, .001)
for x in (-.128, .128):
    box("Top corner rubber", (x, .003, .046), (.022, .100, .018), rubber, .006)
    box("Bottom corner rubber", (x, .004, -.067), (.022, .101, .021), rubber, .006)
    for y in (-.028, .034):
        box("Foot", (x * .86, y, -.078), (.029, .020, .011), rubber, .003)

for x in (-.058, .052):
    box("Handle anchor", (x, .015, .055), (.021, .028, .008), dark_steel, .003)
    box("Handle riser", (x, .015, .066), (.013, .015, .024), rubber, .003)
    screw(x, .027, .056, back=True)
box("Carry handle", (-.003, .015, .080), (.128, .020, .017), rubber, .005)
for index in range(9):
    box("Handle ribs", (-.040 + index * .0092, .008, .085), (.002, .013, .006), dark_steel, .001)

for x in (-.120, .120):
    for z in (-.060, .034):
        screw(x, -.0525, z)

# The dark inset remains visible between the stamped louvers at shallow angles.
box("Speaker rim", (-.063, -.051, -.012), (.100, .009, .093), dark_steel, .005)
box("Speaker cavity", (-.063, -.0557, -.012), (.090, .0025, .082), deep, .004)
for i in range(11):
    z = -.047 + .007 * i
    box("Speaker louver", (-.063, -.058, z), (.079, .0054, .0033), dark_steel, .0011)
    box("Louver edge", (-.063, -.0601, z + .0008), (.075, .0006, .00075), steel)

# Raised dial frame, faded scale bands and a physical red needle.
box("Dial gasket", (.057, -.052, .018), (.109, .009, .046), deep, .004)
box("Dial rim", (.057, -.057, .018), (.101, .005, .040), dark_steel, .0025)
box("Dial scale card", (.057, -.059, .018), (.092, .002, .033), cream, .0014)
for level in (.014, .024):
    box("Scale baseline", (.056, -.0601, level), (.081, .0003, .00075), ink)
    for i in range(25):
        length = .0041 if i % 4 == 0 else .0021
        box("Scale tick", (.017 + i * .00325, -.0603, level + length / 2),
            (.00072, .0003, length), ink)
box("Dial pointer", (.069, -.061, .019), (.00155, .0008, .030), red)
for x, number in ((.018, "4"), (.034, "6"), (.051, "9"), (.077, "12"), (.095, "16")):
    stencil(number, x - .003, .029, .0053, ink, -.0607)
stencil("SW", .018, .006, .006, ink, -.0607)

for x, radius, mark in ((.035, .015, -.52), (.085, .018, .87)):
    z = -.029
    cylinder("Knob shaft collar", (x, -.050, z), (x, -.058, z), radius + .004, deep, 16)
    cylinder("Fluted Bakelite knob", (x, -.057, z), (x, -.070, z), radius, rubber, 16)
    for i in range(16):
        angle = i * pi / 8
        p = (x + sin(angle) * radius, -.063, z + cos(angle) * radius)
        box("Knob flute", p, (.0017, .009, .0032), dark_steel, .0005, angle)
    cylinder("Recessed knob cap", (x, -.070, z), (x, -.071, z), radius * .74, panel, 16)
    box("Knob index", (x + sin(mark) * radius * .54, -.0713, z + cos(mark) * radius * .54),
        (.0017, .0006, .0062), cream, .0004, mark)
stencil("R-16   SHORTWAVE", .006, -.062, .0080, material("Faded stencil ink", (.48, .46, .35), .89))
cylinder("Recessed pilot lamp collar", (.004, -.052, -.030), (.004, -.058, -.030),
         .0052, dark_steel, 10)

# Folded three-section antenna with pivot, insulated tip and retaining clip.
cylinder("Antenna pivot housing", (-.108, -.038, .055), (-.108, -.038, .067), .009, deep)
cylinder("Antenna hinge", (-.108, -.046, .068), (-.108, -.028, .068), .0075, dark_steel)
cylinder("Antenna hinge pin", (-.108, -.047, .068), (-.108, -.029, .068), .0033, steel)
cylinder("Antenna sleeve", (-.106, -.037, .070), (.034, -.037, .070), .0040, steel, 10)
cylinder("Antenna middle draw", (.034, -.037, .070), (.088, -.037, .070), .0031, steel, 10)
cylinder("Antenna inner draw", (.088, -.037, .070), (.115, -.037, .070), .0023, steel, 10)
cylinder("Antenna tip", (.115, -.037, .070), (.123, -.037, .070), .0037, rubber, 10)
box("Antenna retaining block", (.101, -.037, .059), (.013, .017, .013), rubber, .0025)

# Rear compartment and side hardware are modeled for inspection and dropping.
box("Battery compartment gasket", (.026, .051, -.029), (.151, .004, .074), deep, .005)
box("Stamped battery door", (.026, .054, -.029), (.144, .005, .068), shell, .004)
box("Battery thumb catch recess", (.026, .057, -.003), (.036, .0014, .010), deep, .0015)
for x in (.015, .021, .027, .033):
    box("Catch grip rib", (x, .058, -.003), (.0020, .0014, .006), steel, .0004)
for x in (-.113, .111):
    for z in (-.062, .033):
        screw(x, .051, z, back=True)
for i in range(5):
    box("Recessed rear vent", (-.088, .0513, -.018 - i * .006), (.034, .0011, .0026), deep, .0007)
box("Battery door fabric patch", (-.020, .057, -.035), (.012, .001, .040), tape, .001, -.15)
for z in (-.007, .014):
    cylinder("Side socket collar", (.135, -.017, z), (.140, -.017, z), .007, dark_steel)
    cylinder("Side socket liner", (.139, -.017, z), (.1404, -.017, z), .0043, deep)
box("Side belt loop base", (-.138, .014, .006), (.004, .029, .041), panel, .003)
for z in (.020, -.008):
    box("Belt loop standoff", (-.142, .015, z), (.009, .011, .007), dark_steel, .001)
box("Belt loop bridge", (-.147, .015, .006), (.005, .011, .035), dark_steel, .001)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.join()
bpy.context.object.name = "R16Receiver"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", export_animations=False)
