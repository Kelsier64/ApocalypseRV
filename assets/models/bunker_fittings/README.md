# Bunker fittings

Authored metre-scale Godot meshes for the production bunker v2 rooms. The compressed ArrayMesh resources contain beveled parts, pipework and assigned materials. They reuse the project's industrial worn-paint texture. The three stain meshes embed small mipmapped alpha masks.

- `guarded_batten.res` is centred on the original lamp housing. `fluorescent_pair.res` uses the original tube position and receives the room's on/off material.
- Furniture and the pressure door use floor-level origins. Collisions and interaction nodes belong to their existing scene wrappers.
- `transit_chest.res` contains the open body. `transit_lid.res` is relative to `Visuals/LidPivot` at `(0, 0.68, -0.3)`.
- Pipe, cable and tray runs use the six-metre room's original lengths. Room instances scale their longitudinal axis.
- `salvage_engine.scn` retains separate material meshes, including `ValveCover`, for `EngineAppearance`. `scrap_casting.res` fits the original 0.3 m scrap bounds.

2026-11-05 checks covered material assignments in all 16 room scenes, 24 fixtures switching off, cache hinge restoration and engine wear. Forward+ assembled seed 42 with 12 rooms across three floors. Contextual captures checked the lamp, entrance, cache and engine. These checks do not cover every seed or free-play traversal. Authoring intermediates, logs and captures are under the ignored `.godot/bunker-finish-work/` directory.
