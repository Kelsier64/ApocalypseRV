# Bunker Bunk Bed

- Runtime: `assets/models/bunker_bunk_bed/bunker_bunk_bed.glb`; editable glTF, geometry BIN and three PBR PNGs in `editable/`. Generation input: `reference.png`.
- Bounds: X [-1, 1], Y [0, 1.85], Z [-0.45, 0.45] m. Bottom-center origin, +Y up, long axis X, front/ladder +Z, unit scene scale.
- Two-tier chipped olive steel frame, thin stained pale mattresses, one crumpled olive blanket, contained front ladder, open gap between tiers and under lower bed. Bedding remains within the specified footprint; no debris, animations or gameplay scripts.
- Reference produced with built-in imagegen. Prompt: single isolated two-tier military barracks bunk, slender steel frame, distinct mattresses/open tiers, integrated front ladder, one contained crumpled blanket, subtle rust and matte low saturation industrial horror game art, transparent background, no environment/text/debris.
- TRELLIS.2 raw: 49,872 triangles; final: 5,982 triangles / 6,459 vertices, one mesh/material. Original three texture bytes retained. Generation/reduction/fit hashes and settings: `model_parameters.json`; raw remains in ignored local evidence.
- Only `bunk_bed_graybox.tscn:Visuals/Model` replaced. Original node names, StaticBody3D, collision volume and three hall_03/medium_01 placements preserved; graybox children retained hidden.
- Original/reduced textured and clay views compared, including ends, back, top and underside; tiers, ladder and open silhouette remain legible. Final normal/tangent checks passed.
- Topology limitation at 1 micrometer position weld: 45 nonmanifold edges and 12 duplicate triangles; zero open edges and zero zero-area triangles. Existing independent collision retained.
- Native Forward+ context and assertions passed dimensions, bottom origin, existing collision and all three room poses. hall_03 has an existing column blocking some frontal viewing angles; medium_01 preview shows the complete integrated bunk. Room configuration retained.
- `test_interior_navigation.gd` and `test_bunker_lighting.gd` passed 2026-10-10. No manual player walkthrough or FPS benchmark.
- Generated for this task; no third-party source model used.
