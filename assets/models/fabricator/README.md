# Extendable fabricator and printable player

The five machine GLBs are new beveled, UV-mapped Blender parts: base, modular mast, rigid fore/aft gantry, cross carriage and extruder head. They reuse the production scrapper's embedded `teal`, `dark`, `steel`, `orange` and `edge` materials, including base color, metallic/roughness and normal maps. The new cyan nozzle material is separate. Godot units are metres, Y up.

`equipment/fabricator_rig.gd` grows overlapping mast sections to the current deposition height; no maximum height is encoded. The cross carriage moves on Z, its head on X, and the entire gantry on Y. Static horizontal rails retain their dimensions. Parked parts stay outside the output footprint. The recipe/physics clearance rules still apply to the surrounding world.

`printed_player.glb` is a unit-scale static bake of all eleven production `player_test_v020` meshes at the `player_animations_v021` idle pose, approximately 1.6m tall. UVs and surface materials are retained; weights, controllers and animations are removed. `props/printed_player.tscn` rotates the source +Z facing to the game's -Z forward. Injured dormant bodies use cached static anatomical pieces from the existing dismemberment donor.

Editable machine part sources from this work are preserved under ignored `.godot/fabricator_*_source.blend`. These are authoring intermediates; the game uses only the GLBs. Preview controls and feature validation: [fabricator validation](../../../docs/validation/2026-10-11-fabricator-print.md).

`printed_player_crouching.glb` is the same eleven meshes baked at the production `crouch_bent.res` idle pose, with unit scales and feet near Y=0. Its measured height is about 1.03m, fitting the 1.05m crouched contact volume. Both body poses retain the original textures; no mesh squashing is used. `-- --crouch` selects this pose in the print playground.
