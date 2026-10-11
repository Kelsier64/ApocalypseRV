# Player crouch

Two Godot AnimationLibrary variants share the existing v020 player skeleton. Each contains `idle` (2 s) and `forward`, `back`, `left`, `right` (0.6 s each), baked at 60 Hz. All tracks target `PLAYER_Rig/Skeleton3D` bones; the actor has no root motion.

`crouch.res` preserves the original deep squat, including the relaxed arm correction. `crouch_bent.res` is the new default: higher hips, less knee flexion, and a stronger forward bend through the pelvis and lower back. The head stays raised to look ahead; arms hang with bent elbows and relaxed wrists. Both variants have a small alternating arm swing during movement.

Directional cycles alternate support with a 42 cm planted-foot travel over 60% of each cycle. The runtime matches playback to actual movement speed. Foot targets were corrected against evaluated boot skin; rest transforms, weights, meshes and triangle counts are unchanged. These are native bone-animation assets and require no duplicate character model or texture. Once the actor is ready, assign either library to `Visuals/Locomotion.crouch_clips` to choose a variant; input, collision, camera and carry behavior are shared.

Validate both variants' geometry with `test_player_animation_skin`, default behavior with `test_player_crouch`, and item grips with `test_player_carry`. Visual review: `godot --path . --log-file .godot/crouch-review.log res://tests/player_animation_playground.tscn -- --crouch`; F3 plays the four directions, first-person view and low tunnel. Replace `--crouch` with `--crouch-relaxed` to compare the preserved original. Captures go to ignored `.godot/crouch-bent-review/` and `.godot/crouch-relaxed-review/` respectively.
