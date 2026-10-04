# Ruined concrete wall study material

Created 2026-10-03 for an independent close-up wall study. `aggregate_albedo.png` is an AI-generated base-color texture created with the built-in imagegen tool, not a photograph or a calibrated scan. The original output was copied into the project; no runtime asset references depend on Codex's generated-images directory. The exact generation prompt is preserved in [the authoring folder](../../../art_source/ruined_wall/prompt.md).

`concrete.gdshader` blends this exposed-aggregate texture with the project's existing concrete texture. Mesh vertex red stores the authored erosion amount. Fine bump is an artistic derivative of image intensity, not a measured normal/height scan. Roughness, wet dirt and mineral/rust runoff are shader-authored. Mipmaps and anisotropic sampling suppress fine aggregate aliasing.

Consumer: [ruined_wall_study.tscn](../../../world/art_samples/ruined_wall_study.tscn). This independent art sample has not replaced production shelter geometry. The original concrete texture's provenance remains in [its README](../poi_kit/README.md).

The production shelter's [formed concrete material](../../../world/starting_shelter/materials/formed_concrete.tres) also reuses `aggregate_albedo.png` for its authored recessed damage, with mipmapped sampling and reduced contrast. This is texture reuse only; the high-density study mesh and its shader remain independent.
