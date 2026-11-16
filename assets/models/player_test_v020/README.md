# Player v020 asset

The production [player visual](../../../player/player_model_visual.tscn) now instances this accepted GLB. The original fixture path is retained so the import and ragdoll evidence still resolve to the exact same asset.

- Source: `C:/Users/evan4/Projects/3d/player_textured_v019.blend`, preserved.
- Export copy: `C:/Users/evan4/Projects/3d/player_godot_export_v020.blend`.
- Delivery GLB: `C:/Users/evan4/Projects/3d/exports/godot/player_export_test_v020.glb`; this directory contains an identical copy.
- 11 skinned mesh objects, 41 deform bones, 16,222 triangles, 5 materials, one embedded 512px Base Color PNG.
- Upright Y, source front +Z, feet at origin, height 1.60 m, no scale/rotation correction.
- Only `TEST_v020_POSE_SAMPLES` (8 seconds); no production animations.

Keep the adjacent `.glb.import` settings: animation optimizer off, 24 fps, named skins, no retarget/rest replacement. The optimizer's default curve reduction changed the accepted pose samples. Source mask Base Color is 0.9 linear RGB, despite its PureWhite name; no source material was changed.

Run [the isolated playground](../../../tests/player_import_v020/playground.tscn).
The user subsequently approved continuing and left the mask constant to our discretion; 0.9 is retained.
Run [the independent ragdoll playground](../../../tests/player_ragdoll_v020/playground.tscn) for physics testing.

Production removes the TEST library references from its own AnimationPlayer instance and installs the separate v021 locomotion library. The asset itself retains the validation clip. Visuals rotate 180 degrees around Y to align this +Z-facing asset with the controller's -Z forward; there is no axis-conversion correction or rescaling. Local head culling and full shadows are presentation copies, never source geometry or weight edits. Death ragdoll now uses the accepted 14-body rig in the production Player. See [v021 locomotion](../player_animations_v021/README.md) for the current authored clips.
