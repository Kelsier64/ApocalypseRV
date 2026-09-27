# Player v020 import test asset

This isolated fixture is not referenced by the production player or main world.

- Source: `C:/Users/evan4/Projects/3d/player_textured_v019.blend`, preserved.
- Export copy: `C:/Users/evan4/Projects/3d/player_godot_export_v020.blend`.
- Delivery GLB: `C:/Users/evan4/Projects/3d/exports/godot/player_export_test_v020.glb`; this directory contains an identical copy.
- 11 skinned mesh objects, 41 deform bones, 16,222 triangles, 5 materials, one embedded 512px Base Color PNG.
- Upright Y, source front +Z, feet at origin, height 1.60 m, no scale/rotation correction.
- Only `TEST_v020_POSE_SAMPLES` (8 seconds); no production animations.

Keep the adjacent `.glb.import` settings: animation optimizer off, 24 fps, named skins, no retarget/rest replacement. The optimizer's default curve reduction changed the accepted pose samples. Source mask Base Color is 0.9 linear RGB, despite its PureWhite name; no source material was changed.

Run [the isolated playground](../../../tests/player_import_v020/playground.tscn).
See [acceptance report and screenshots](../../../docs/validation/2026-09-27-player-v020-import.md).
The user subsequently approved continuing and left the mask constant to our discretion; 0.9 is retained.
Run [the independent ragdoll playground](../../../tests/player_ragdoll_v020/playground.tscn) for physics testing.
See [ragdoll acceptance](../../../docs/validation/2026-09-27-player-v020-ragdoll.md) for its scoped Jolt settings, evidence and integration limits.
