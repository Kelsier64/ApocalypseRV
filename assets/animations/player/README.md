# Player crouch

`crouch.res` is a Godot AnimationLibrary for the existing v020 player skeleton. It contains `idle` (2 s) and `forward`, `back`, `left`, `right` (0.6 s each), baked at 60 Hz. All tracks target `PLAYER_Rig/Skeleton3D` bones; the actor has no root motion.

The pose lowers the hips, leans the torso and bends both knees. Directional cycles alternate support with a 42 cm planted-foot travel over 60% of each cycle. The runtime matches playback to actual movement speed. Foot targets were corrected against evaluated boot skin; rest transforms, weights, meshes and triangle counts are unchanged. These are native bone-animation assets and require no duplicate character model or texture.

Validate geometry with `test_player_animation_skin` and behavior with `test_player_crouch`. Visual review: `godot --path . --log-file .godot/crouch-review.log res://tests/player_animation_playground.tscn -- --crouch`; F3 plays the four directions, first-person view and low tunnel. Captures go to ignored `.godot/crouch-review/`.
