# Ruined wall close-up study

`ruined_wall_study.tscn` is a standalone, inspectable Godot art sample made for the request to see a much more realistic, severely damaged wall. It is not wired into `main_world` and has no gameplay/save state or collision contract.

- Design envelope: 4.8 m wide, up to 3.4 m tall, 0.46 m thick, ground at Y=0, frontage toward +Z.
- Actual geometry: irregular top silhouette, continuous recessed spalling, a through-hole with solid inner surfaces, exposed ribbed steel rods, branching cracks, and fallen concrete pieces.
- Shader: aged outer cement versus exposed aggregate, subtle bump, dark lower damp, brown runoff; [material provenance](../../assets/materials/ruined_wall/README.md).
- Close-up study mesh density is intentionally higher than production walls. Integration would need collision authoring and an appropriate production LOD/performance pass.

Run `godot --path . res://world/art_samples/ruined_wall_study.tscn`. F1 selects the overall view; F2 selects the broken-concrete/rebar detail; F12 exports the active view to `art_source/ruined_wall/preview.png` or `detail.png`. `-- --capture` exports the overall image after rendering settles. These are actual Godot viewport exports, not generated concept images. The sample forces native 3D resolution and 4x MSAA on its own viewport for inspection.

Offline authoring source: [build_ruined_wall_study.gd](../../scripts/build_ruined_wall_study.gd). Run with `godot --headless --path . -s res://scripts/build_ruined_wall_study.gd -- --write` to regenerate this scene only. Mesh edits should be maintained in that script; ordinary gameplay does not run it.

Validated 2026-10-03: Godot import and offline authoring completed; Forward+ overall and close-up views were inspected. Fixed contour clipping and inner-side winding, enabled aggregate mipmaps, and exported [overall](../../art_source/ruined_wall/preview.png) and [detail](../../art_source/ruined_wall/detail.png) renders. Final render log `.godot/wall-study-final.log` records both successful exports with no shader/script errors. This is visual validation only; production gameplay tests and collision/navigation integration were not part of this standalone sample.
