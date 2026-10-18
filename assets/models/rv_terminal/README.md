# WAYFARER vehicle terminal

Original landscape housing model made directly in Blender; no ComfyUI or
third-party generated assets. There are no physical buttons or rotary controls.
`rv_terminal.glb` contains one static mesh, 3,478 triangles and five material
surfaces. The Godot display adds two triangles and one surface: 3,480 triangles
and six surfaces total, within a 4,000-triangle budget for one close-view terminal.

Godot bounds and the Item collider are 0.4 × 0.05 × 0.6 m, centred at the origin.
The front faces +Y; screen up is +X and right is +Z. The existing 90° Z wall
mount therefore displays a 0.6 m wide × 0.4 m high landscape terminal. Rear
mounting runners and corner protection remain inside this envelope.

`overview.png` is a 1536 × 864 static, simplified overview based on the actual
[rvctl UI](../../../equipment/tablet_ui.gd), [theme](../../../equipment/terminal_theme.gd)
and [character-cell panels](../../../equipment/terminal_panel.gd), using the same
Noto Sans Mono font. It retains the header, five page names, vehicle status,
attention and body condition; removes action buttons, keyboard hints and dense
telemetry. Values are a parked starter-RV reference, not live world telemetry.
The texture uses lossless compression and mipmaps. Runtime interaction and live
vehicle data continue to use the original terminal UI.

[Visual wrapper](../../../rv/visuals/tablet_screen.tscn) holds the housing and
textured display; [Item wrapper](../../../equipment/tablet_screen.tscn) retains
the root, legacy Mesh anchor, gameplay script and resized collider.

2026-10-15 validation: Godot 4.7.2 Forward+ close/cabin renders verified landscape
placement, upright text, no physical controls, matching visual/placement/collider
bounds, centred origin and inward-facing installation. The unified runner passed
`test_rv_tablet_ui` and `test_item_player`. No manual gameplay walkthrough was
performed. The sandboxed render logged an unavailable user shader-cache directory;
no script or shader compilation errors in the final render. Authoring source,
real UI reference and review outputs are ignored under `.godot/terminal-model/`.
