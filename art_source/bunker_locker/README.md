# Bunker Locker

- Runtime: `assets/models/bunker_locker/bunker_locker.glb`; editable glTF, geometry BIN and three PBR PNGs are in `editable/`. `reference.png` is the unmarked generation input.
- Design bounds: X [-0.31, 0.31], Y [0, 1.9], Z [-0.29, 0.29] m. Bottom-center origin, +Y up, front/handle +Z; unit scene scale.
- Single closed olive steel locker with wear, shallow dents and a readable recessed handle. No number stencil, text, loose parts, animations or internal mechanics.
- 2,998 triangles and 2,186 vertices, one mesh/material. 50,000-triangle raw generation retained in ignored local work; three texture bytes unchanged during reduction. Parameters/hashes: `model_parameters.json`.
- Only `locker_graybox.tscn:Visuals/Model` is changed. Existing node names, StaticBody3D, CollisionShape3D and room placements are preserved. Original graybox children remain hidden; the old stencil text is cleared.
- Checked original/reduced views including front, sides, rear, top and underside. At 1 μm position weld: zero open edges, nonmanifold edges, duplicate or zero-area triangles.
- Native Forward+ review in `small_01.tscn` passed dimensions, bottom origin, collision and original node names. All four shared instances in `entry`, `medium_01`, `small_01` load and their rooms validate.
- `test_interior_navigation.gd` and `test_bunker_lighting.gd` passed on 2026-10-09. No manual player walkthrough or FPS benchmark performed.
- Reference/model generated for this task with imagegen/TRELLIS.2; no third-party source model used.
