# Raker v013 — walk, run, vehicle sprint

Editable source: [monster_refined_v013.blend](monster_refined_v013.blend), scene `MONSTER_REFINED_V013`. Keeps previous revisions and their actions. Geometry, UVs, packed dirt textures and the neutral 2.18 m height are unchanged from v012.

- Walk: lowered pelvis, bent knees, bowed head, hanging hands and restrained sway (1.2 s).
- Run / chase: deeper forward lean, higher feet and wider opposing arm swing (0.8 s).
- Vehicle sprint: lowest torso, long strides, forceful arm swing (0.6 s).

The 20 other clips are retained. All 23 clips are in-place: Godot owns movement. Source v012 has 8,060 vertices, 16,116 triangles and 45 deform bones.

With v012 or this blend loaded, run [author.py](author.py), then [audit.py](audit.py) and [finish.py](finish.py) through Blender MCP. Authoring copies the v012 scene and bakes constrained poses from the preserved source rig into new actions. NLA tracks export canonical `walk`, `chase`, `sprint` names; historical actions are not overwritten. Reruns keep superseded v013 actions for review; exported tracks always reference the latest bake.

Copy [raker_refined_v013.glb](raker_refined_v013.glb) to [production raker.glb](../../assets/models/raker/raker.glb), then run the Raker suite and main-world model test. The export temporarily supplies stable `Raker_Rig` / `Raker_Mesh` names.

[validation.json](validation.json) records 23 clips / 748 sampled frames with no nonadjacent triangle intersections. New locomotion clips stay above the ground to floating-point tolerance. Shared-vertex pairs are excluded; arbitrary animation blends and terrain foot contacts are not exhaustively checked. No terrain foot IK is implemented; high-speed turns may slide.

Preview: [walk](walk.png), [run](chase.png), [sprint](sprint.png).
