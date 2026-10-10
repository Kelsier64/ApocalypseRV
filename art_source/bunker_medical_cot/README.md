# Bunker Medical Cot

- Runtime: `assets/models/bunker_medical_cot/bunker_medical_cot.glb`; editable glTF, geometry BIN and three PBR PNGs are in `editable/`. `reference.png` is the generation input.
- Bounds: X [-1.05, 1.05], Y [0, 0.85], Z [-0.475, 0.475] m. Bottom-center origin, +Y up, long axis X, patient access +Z; unit scene scale.
- Thin worn enamel steel frame, four legs, low end hoops, dirty pale mattress and one restrained dark blood stain. Open space below the bed and open long access side; no carts, clutter, animation or gameplay scripts.
- 3,999 triangles, 3,820 vertices, one mesh/material; original 50,000 triangles retained in ignored local work. Three texture bytes preserved during reduction. Settings, fit, hashes and limitations: `model_parameters.json`.
- Only `medical_cot_graybox.tscn:Visuals/Model` receives the GLB. All original node names, StaticBody3D, CollisionShape3D and both room placements remain unchanged. Graybox meshes remain hidden.
- Original/reduced textured and clay views were compared, including sides, ends, top and underside; legs and open under-bed silhouette remain. Topology limitation at 1 μm position weld: 3 open edges, 11 nonmanifold edges and 4 duplicate triangles; no zero-area faces. Original independent collision retained.
- Native Forward+ review in `medium_02.tscn` passed bounds, bottom origin, original node names/collision, both existing cot poses and room validation.
- Existing layout issue: first cot envelope spans room Z [-2.40, -0.30], wall_shelf_2 spans [-0.60, 0.60]; their envelopes overlap by 0.30 m. The shelf enters the bed-head area in the context preview. Placement and collision are preserved per request.
- `test_interior_navigation.gd` and `test_bunker_lighting.gd` passed on 2026-10-10. No manual player walkthrough or FPS benchmark performed.
- Reference/model generated for this task using imagegen/TRELLIS.2; no third-party source model used.
