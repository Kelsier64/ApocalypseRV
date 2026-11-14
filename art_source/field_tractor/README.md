# Field Tractor

- Runtime: `assets/models/field_tractor/field_tractor.glb`, wrapped by `field_tractor.tscn` (visual plus three static collision boxes). Editable glTF, geometry BIN and three PBR PNGs are in `editable/`; `reference.png` is the generation input.
- Design bounds: X [-0.89, 0.89], Y [0, 1.79], Z [-1.45, 1.45] m. Bottom-center origin, +Y up, grille +Z; unit scene scale (uniform 2.9x of the raw model).
- One abandoned small farm tractor: faded red paint mostly rusted through, exposed engine, cracked flat tyres, bare seat. No lettering, plates, loose parts or animation.
- 10,470 triangles and 13,386 vertices, one mesh/material, reduced from the 49,898-triangle raw generation with gltfpack 1.3 (`-si 0.12 -se 0.025`). The raw GLB stays in ignored local work; texture bytes are unchanged. Parameters and hashes: `model_parameters.json` (prompt ID `fd3515e0-9368-492c-8fb3-55893e9c9be6`, seed 42, profile `trellis-single-1024-50k`).
- Known topology: 203 non-manifold edges and 82 duplicate triangles at 1 μm weld, inherited from the generated mesh; none is visible in the reviewed views.
- Reviewed raw and final in six views (front, side, back, oblique, top, underside), textured and clay: complete silhouette, four wheels, steering wheel and seat intact, no fused or missing parts.
- Used only by the `tractor` field vignette in `world/scatter/feature_builder.gd`, which falls back to a native stand-in if this scene is absent.
- Reference prompt (Gemini via agy, 2026-11-13): "one abandoned small farm tractor from the 1970s, complete with four wheels, faded dull red paint almost entirely replaced by brown rust, flat cracked tyres, missing engine cover, no driver, standing level on its wheels", low-poly survival-horror style, transparent background, no text. Model generated with local TRELLIS.2; no third-party source model used.
