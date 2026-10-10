# Bunker Switchgear

- Runtime: `assets/models/bunker_switchgear/bunker_switchgear.glb`; editable glTF, geometry BIN and three PBR PNGs in `editable/`. Generation reference: `reference.png`.
- Bounds: X [-0.60, 0.60], Y [0, 2.35], Z [-0.36, 0.36] m. Bottom-center origin, +Y up, operable panel +Z, unit scene scale.
- Tall olive-gray steel cabinet, scorched recessed access doors, three breaker handles, worn hazard stripes/lightning symbol, contained wiring; closed back and base. Static visual only.
- Reference made using built-in imagegen. Prompt: isolated front-three-quarter tall bunker switchgear, muted olive steel, coarse matte wear/soot, recessed breakers and contained wires, faded hazard symbols, simplified industrial horror game art, transparent background, no text/numbers/environment.
- TRELLIS.2 raw: 49,938 triangles; reduced: 3,995 triangles / 4,427 vertices, one mesh/material. Original three texture bytes retained. Settings, hashes and topology: `model_parameters.json`; raw model remains in ignored local evidence.
- Only `switchgear_graybox.tscn:Visuals/Model` replaced. Original node names, StaticBody3D, collision, interactions and both hall_02/large_02 placements preserved; graybox children retained hidden.
- Compared original/reduced textured and clay views, including back, sides, top and underside; panel details and cabinet silhouette retained. Two raw tangent orthogonality issues corrected in the working copy; all final normal/tangent checks passed.
- Topology limitation at 1 micrometer position weld: 3 open edges, 57 nonmanifold edges and 17 duplicate triangles; no zero-area triangles. Rendering uses existing independent wrapper collision.
- Native Forward+ hall_02 contextual render and assertions passed dimensions, origin, original collision and both room poses. `test_interior_navigation.gd` and `test_bunker_lighting.gd` passed 2026-10-10. No manual gameplay or FPS benchmark.
- Generated for this task; no third-party source model used.
