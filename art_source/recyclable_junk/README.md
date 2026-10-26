# Recyclable junk props

Six original props made with imagegen references and the local ComfyUI TRELLIS.2 workflow on 2026-10-27. The steel plate reference was revised to remove its diagonal fold and reduce the lifted corner, as requested. No military transport chest or opening supply chest was made.

| Prop / source folder | Game bounds, cm (X/Y/Z) | Mass, kg | Raw / game triangles |
| --- | --- | ---: | ---: |
| [Steel plate](bent_steel_plate/) | 55 / 2.5 / 41.7 | 6 | 49,992 / 3,996 |
| [Broken pipe elbow](broken_pipe_elbow/) | 35.3 / 32.5 / 40 | 5 | 46,936 / 15,978 |
| [Brake drum](rusted_brake_drum/) | 32 / 12.1 / 32 | 6 | 49,998 / 4,996 |
| [Exhaust muffler](old_exhaust_muffler/) | 55 / 17.8 / 22.7 | 4.5 | 49,988 / 4,998 |
| [Paint bucket](dented_paint_bucket/) | 31 / 40 / 27.7 | 1.5 | 49,984 / 4,994 |
| [Electric iron](discarded_electric_iron/) | 33 / 17.4 / 14.3 | 2.5 | 49,258 / 7,542 |

## Assets and reconstruction

Runtime models are in [assets/models/scavenge_loot](../../assets/models/scavenge_loot/), Item scenes in [props/scavenge_loot](../../props/scavenge_loot/), and rendered 256 px inventory icons in [assets/inventory](../../assets/inventory/). Each source folder retains the actual `reference.png`, untouched `raw.glb`, ComfyUI provenance in `generation.json`, and preparation parameters in `model_parameters.json`. The source tree is excluded from Godot imports by the existing parent `.gdignore`.

Each model used one submission: 1024, seed 42, target approximately 50k triangles, profile `trellis-single-1024-50k`. Backend 8189 was already available; the default 8188 service was unresponsive. No backend was interrupted or restarted. Intermediate jobs, renders, tools and logs remain in the ignored `.godot/art-work/recyclable_junk/20261027-01/`.

Use the shared [static prop tool](../../.agents/skills/comfyui-image-to-3d/references/static-props.md) with the recorded size, Y rotation, `bottom-center` origin, and gltfpack 1.3 flags to reproduce the runtime geometry. Most dimensions preserve generated proportions, rounded to millimetres; the steel plate's height is deliberately reduced to a 2.5 cm overall envelope, including shallow edge unevenness. This is not a uniform 2.5 cm material thickness.

Total geometry falls from 296,156 to 42,504 triangles. Ratios are 0.08 for the plate, 0.12 for the elbow, and 0.10 otherwise. The finite simplification error is 0.025 except for the elbow's 0.05. The elbow retains approximately 16k triangles because the bounded reduction was limited by its generated topology; a first 0.025 candidate retained approximately 18k. Original embedded texture bytes are preserved. One collapsed tangent each on the raw elbow and drum is repaired on the working copy by the shared preparation tool.

## Gameplay

All six are normal inventory Items with independent primitive collisions, centred rigid-body origins, and default `Metal Parts` yield 2–5. The drum uses a cylinder; the others use boxes. Handles and holes are visual details, not precise collision openings.

[ScavengeLoot](../../core/scavenge_loot.gd) selects among the six props and legacy scrap using a stable opportunity key, without consuming the existing generation RNG. Fresh world scrap, walk-in POI scrap and bunker supplies use this pool. Existing saved actors keep their scene. Bunker per-instance yields are retained; the opening tutorial's stock and resource totals are unchanged. Variant placement uses its actual bounds so frozen bunker loot rests on the floor and POI variants preserve the authored legacy scrap bottom.

## Review and limits

Raw and final models were inspected from front, side, back, oblique, top and underside in both textured and lit clay renders. The plate is mostly flat; the other objects retain their main silhouette, visible recesses and handle gaps. These remain generated static visuals with non-manifold edges and duplicate triangles, recorded per model; they are not clean manifold solids or precision mechanical parts.

Godot 4.7.2 context renders placed the six production Item scenes at real scale on the existing utility tables and floor in `small_02.tscn`. Both views were inspected for proportions, materials and support contact; measured bounds align with the 0.86 m table top and floor to 2 micrometres. This checks bounding-envelope placement, not exact support-plane flatness. Images, measurements and the clean log remain in the ignored run directory. This was a staged render, not manual exploration of random layouts.

Current automated checks passed:

- `test_item_player.gd`: native E pickup, inventory serialization, carry at three camera pitches, drop and world restoration for all six new Items; fresh POI substitution, bottom alignment, scene catalog, unchanged fuel rolls and bunker recycling RNG. The initial pipe yaw put its held bounds too close to the eye when looking down; the final wrapper uses `hold_rotation = Vector3(-8, 0, 0)` and the suite passes. Final log: `.godot/test-logs/20261027-003713-785-selected-51348/test_item_player.log`.
- `test_orientation_departure.gd`: production tutorial stock and repair/recycle/departure journey. Log: `.godot/test-logs/20261027-003724-006-selected-14132/test_orientation_departure.log`.
- A headless fixture dropped each of the six production Items into the installed RV recycler by gravity. All were accepted, shredded and credited exactly once; a pre-decided three-metal return per Item produced 18 total. The fixture starts above the actual hopper shape, below the RV roof. Clean log: `.godot/art-work/recyclable_junk/20261027-01/recycler_verified.log`.
- Project import and context-render logs contain no script errors; `git diff --check` passes.

No full suite, manual carry-animation review, random-layout exploration or crowd/many-prop performance test was run for this change.
