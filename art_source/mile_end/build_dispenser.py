"""Run with Blender --background --factory-startup --python to export the original pump."""
from pathlib import Path
from math import pi

import bpy

OUT = Path(__file__).resolve().parents[2] / "world/roadside_pois/mile_end"
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

def coat(name, rgb, metal=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb, 1)
    shader.inputs["Metallic"].default_value = metal
    shader.inputs["Roughness"].default_value = 0.65
    return mat

teal = coat("Oxidized enamel", (.052, .145, .131), .32)
ivory = coat("Faded porcelain", (.62, .53, .36), .18)
red = coat("Oxide red", (.32, .092, .048), .22)
iron = coat("Black iron", (.063, .057, .045), .54)
chrome = coat("Brushed nickel", (.38, .38, .31), .72)
rubber = coat("Worn hose rubber", (.025, .031, .027))
dial = coat("Mechanical register", (1,1,1))
tex = dial.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = bpy.data.images.load(str(Path(__file__).resolve().parents[2] / ".godot/mile-end-art/register.png"))
dial.node_tree.links.new(tex.outputs["Color"], dial.node_tree.nodes["Principled BSDF"].inputs["Base Color"])

def block(name, pos, dims, mat, bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    mod = obj.modifiers.new("Cast corners", "BEVEL")
    mod.width, mod.segments = bevel, 3
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod = obj.modifiers.new("Face normals", "WEIGHTED_NORMAL")
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def pipe(name, points, radius, mat):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions, curve.resolution_u = "3D", 6
    curve.bevel_depth, curve.bevel_resolution = radius, 2
    line = curve.splines.new("BEZIER")
    line.bezier_points.add(len(points)-1)
    for p, xyz in zip(line.bezier_points, points):
        p.co = xyz
        p.handle_left_type = p.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj.select_set(False)

block("Anchor shoe",(0,0,.085),(.77,.62,.17),iron,.045)
block("Pressed plinth",(0,0,.22),(.70,.54,.19),teal,.06)
block("Lower cabinet",(0,0,.72),(.59,.49,1.04),teal,.087)
block("Waist ring",(0,0,1.17),(.67,.55,.09),chrome)
block("Meter housing",(0,0,1.55),(.81,.58,.76),ivory,.12)
block("Crown",(0,0,1.93),(.79,.55,.12),red,.055)
for side in [-1,1]:
    block("Meter bezel",(0,side*.289,1.58),(.65,.032,.46),iron,.032)
    bpy.ops.mesh.primitive_plane_add(size=1,location=(0,side*.309,1.58))
    face = bpy.context.object
    face.rotation_euler = (pi/2,0,0 if side==-1 else pi)
    face.scale = (.603,.401,1)
    face.data.materials.append(dial)
    block("Service hatch",(0,side*.249,.69),(.43,.018,.68),red,.036)
    for z in [.54,.59,.64,.69]:
        block("Vent",(0,side*.262,z),(.23,.014,.013),iron,.004)
for obj in bpy.context.selected_objects:
    obj.select_set(False)
pipe("Slack delivery hose",[(.38,.02,1.66),(.60,.03,1.46),(.70,0,.48),(.55,-.04,.28),(.43,-.10,.51),(.50,-.14,1.05)],.032,rubber)
pipe("Cast nozzle",[(.50,-.14,1.04),(.49,-.14,1.20),(.42,-.14,1.34)],.045,chrome)
pipe("Trigger guard",[(.49,-.14,1.06),(.57,-.14,1.16),(.48,-.14,1.26)],.013,iron)
bpy.ops.object.select_all(action="SELECT")
bpy.context.view_layer.objects.active = next(o for o in bpy.context.selected_objects if o.type=="MESH")
bpy.ops.object.join()
bpy.context.object.name = "MechanicalDispenser"
bpy.ops.export_scene.gltf(filepath=str(OUT/"dispenser.glb"),export_format="GLB",export_yup=True)
