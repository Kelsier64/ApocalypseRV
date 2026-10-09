# Slender Speaker runtime asset

The production [enemy scene](../../../enemies/slender_speaker/slender_speaker.tscn) uses [slender_speaker_rigged.glb](slender_speaker_rigged.glb): 15 m tall, 35,682 triangles, 55 bones, six materials and six 2048 × 2048 PBR maps. The model faces +Z; the Godot visual wrapper rotates it by 180 degrees.

The GLB contains in-place idle, scan, walk, run, turn, smash, grab, lift, hold, crush and retract clips. The controller blends locomotion with moving attacks and follows actual vehicle contact. Hand-review clips remain embedded in the same model.

Keep the GLB, extracted rigged texture PNGs, their `.import` settings and both Godot import scripts. [import_animation.gd](import_animation.gd) sets animation loops and extends [import_materials.gd](import_materials.gd), which restores the oil clearcoat from the packed map. These scripts are required when importing a fresh checkout.

The model was authored in Blender; patrol and execution audio are original procedural compositions without third-party samples. Editable Blender sources, generation scripts, earlier static exports and review captures remain local and are omitted from this delivery.

[Animation contract test](../../../tests/test_slender_speaker_animation.gd) covers the shipped model. [Runtime playground](../../../tests/slender_speaker_playground.tscn) exercises the production player, RV and enemy; controls are in the [playground guide](../../../docs/guides/playgrounds.md#slender-speaker-runtime). See [PR validation](../../../docs/validation/2026-10-09-slender-speaker-pr.md) for test scope and limits.
