"""Run once through Blender MCP after build_model.py, before animate_export.py."""
import bpy

scene = bpy.data.scenes['BARREL_MAN_AUTHORING']
bpy.context.window.scene = scene
rig = bpy.data.objects['BarrelManRig']
if not rig.get('game_mesh_optimized', False):
    for ob in scene.objects:
        if ob.type != 'MESH' or not (ob.name.startswith('Leg_') or ob.name.startswith('Nail_')):
            continue
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        modifier = ob.modifiers.new('Game_budget', 'DECIMATE')
        modifier.ratio = .74 if ob.name.startswith('Leg_') else .35
        # Collapse the rest mesh, never bake an animated armature pose.
        bpy.ops.object.modifier_move_up(modifier=modifier.name)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        print(ob.name, 'triangles', sum(len(p.vertices)-2 for p in ob.data.polygons))
    rig['game_mesh_optimized'] = True
if not rig.get('sole_grounded', False):
    for ob in scene.objects:
        if ob.type == 'MESH' and ob.name.startswith('Leg_'):
            for vertex in ob.data.vertices:
                # Set the load-bearing sole at root height, smoothly merging
                # into the heel/toes without moving the ankle joint.
                vertex.co.z -= .016 * max(0,min(1,(.06-vertex.co.z)/.038))
    rig['sole_grounded'] = True
