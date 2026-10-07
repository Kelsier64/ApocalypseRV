# Barrel Man runtime asset

Generated through Blender MCP from [editable source and build instructions](../../../art_source/barrel_man/README.md).

`barrel_man.glb` contains the skinned human legs, toenails, 11-bone rig and ten 60 Hz animation clips. The refined ankle/foot/toe revision has 42,846 triangles and one 2048² skin texture. The barrel itself is instantiated from `../oil_barrel/oil_barrel.glb` by `enemies/barrel_man_visual.gd` at the `barrel` bone.

Godot import sampling stays at 60 fps with key reduction disabled to preserve the compact folding poses. Use [the actor scene](../../../enemies/barrel_man.tscn), not the GLB alone, for gameplay. See [original behavior validation](../../../docs/validation/2026-10-07-barrel-man.md) and [refined foot validation](../../../docs/validation/2026-10-07-barrel-man-feet.md).
