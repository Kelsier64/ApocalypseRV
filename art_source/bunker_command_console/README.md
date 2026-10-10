# Bunker Command Console

- Runtime: `assets/models/bunker_command_console/bunker_command_console.tscn`; embedded-texture GLB plus Godot material/shader.
- Editable: `editable/bunker_command_console.gltf`, matching BIN and three PBR PNGs; `reference.png` is the generated image input.
- Exact design bounds: X [-0.9, 0.9], Y [0, 1.2], Z [-0.36, 0.36] m. Bottom-center origin, +Y up, operator side +Z; unit scene scale.
- 5,992 triangles, 6,326 vertices, one mesh/material. Original 49,950-triangle generation retained locally; textures unchanged during reduction. Generation and fit/reduction parameters are in `model_parameters.json`.
- CRTs stay dark. `console.gdshader` intermittently lights a few existing amber atlas lenses using TIME; this Godot effect is not embedded in the standalone GLB. No additional detail meshes, lights, gameplay scripts or animation tracks.
- Only `command_console_graybox.tscn:Visuals/Model` receives the asset. All original node names, collision and both hall placements are preserved; graybox meshes/stencil remain hidden.
- Topology limitation (1 μm position weld): 84 nonmanifold edges and 22 duplicate triangles, no open edges or zero-area faces. Kept for this static visual; collision remains the existing independent box.
- Checked the generated/reduced front, sides, rear and bottom; native Forward+ review in `rooms/bunker/v2/hall_01.tscn` passed dimensions, origin, collision, both poses and room validation. Two timed screenshots confirmed a localized indicator brightness change while screens remained dark.
- Related checks: `test_interior_navigation.gd`, `test_bunker_lighting.gd` passed (2026-10-09). No manual player walkthrough or FPS benchmark performed.
- Reference/model were generated for this task using imagegen/TRELLIS.2; no third-party source model used.
