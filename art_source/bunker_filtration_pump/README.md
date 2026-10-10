# Bunker Filtration Pump

- Runtime: `assets/models/bunker_filtration_pump/bunker_filtration_pump.glb`; editable glTF, geometry BIN and three PBR PNGs are in `editable/`. `reference.png` is the generation input.
- Bounds: X [-0.7, 0.7], Y [0, 1.4], Z [-0.4, 0.4] m. Bottom-center origin, +Y up, inspection panel +Z; unit scene scale.
- One coherent motor, broad filter vessel, thick short manifold pipes and common skid base; olive/steel corrosion and mineral-water staining. Pipes remain inside the design envelope. No loose parts, animation, gameplay scripts or pipe sockets.
- 7,530 triangles, 9,417 vertices, one mesh/material. The ~6k reduction attempt stopped at 7,530 under the selected error limit; retained to preserve pipe/flange forms for close views. Original: 49,920 triangles, kept in ignored local work. Three texture bytes preserved. Generation, fit/reduction settings and hashes: `model_parameters.json`.
- Only `filtration_pump_graybox.tscn:Visuals/Model` receives the GLB. All existing node names, StaticBody3D, CollisionShape3D and room placement remain unchanged. Original graybox children/stencil remain hidden.
- Reviewed original/reduced textured and clay views, including front, rear, sides, top and underside. Topology limitation (1 μm position weld): 115 nonmanifold edges and 38 duplicate triangles; no open edges or zero-area faces. This remains a static visual with independent original collision.
- Native Forward+ review in `hall_02.tscn` passed dimensions, bottom origin, wrapper collision, original node names, existing placement and room validation.
- `test_interior_navigation.gd` and `test_bunker_lighting.gd` passed on 2026-10-10. No manual player walkthrough or FPS benchmark performed.
- Reference/model generated for this task using imagegen/TRELLIS.2; no third-party source model used.
