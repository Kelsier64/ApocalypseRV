# WAYFARER vehicle terminal

Original model made directly in Blender; no ComfyUI or generated third-party assets.
`rv_terminal.glb` contains one static mesh, 7,356 triangles and nine shared material
surfaces. Budget: 8,000 triangles for one close-view, movable terminal per RV.
No textures, lights, collision, scripts or animation are embedded.

Godot bounds are 0.6 × 0.05 × 0.4 m, centred at the origin. The front faces +Y;
screen up is +X and screen right is +Z. This matches the existing terminal's
90° Z rotation on the right cabin wall. Shock boots, rear mounting runners,
control keys and the encoder stay within the original collision envelope.

`../../../rv/visuals/tablet_screen.tscn` instances the asset under `PanelDetails/Model`.
`../../../equipment/tablet_screen.tscn` keeps the Item root, empty legacy `Mesh`
anchor, original collision and gameplay script. The display is decorative idle
art; the existing interactive terminal UI remains responsible for live vehicle data.
Automatic mesh LOD and vertex compression are disabled to preserve fine planar
display artwork; the mesh remains within its budget without simplification.

2026-10-15 validation: Godot 4.7.2 Forward+ renders of the actual starter RV
confirmed upright text, wall placement and close/cabin views. The render check
confirmed 7,356 triangles, nine surfaces and unchanged collision dimensions.
The unified runner passed `test_rv_tablet_ui` and `test_structure_construction`.
No manual gameplay walkthrough was performed. The sandboxed render logged an
unavailable user shader-cache directory; no script or shader compilation errors.
Authoring source and review outputs are ignored under `.godot/terminal-model/`.
