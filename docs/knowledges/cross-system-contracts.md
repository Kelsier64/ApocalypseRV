# Knowledge: Cross-System Contracts

## 1. Why This Matters
- Core gameplay systems are connected through Godot groups and duck-typed method calls instead of strict interface classes.
- Most runtime failures in this project come from scene wiring mistakes (wrong group, missing method, wrong node parent chain), not syntax errors.
- Contract awareness is required before changing player interaction, RV/equipment, or world spawning behaviors.

## 2. Trigger Conditions
- Editing any script that calls `has_method`, checks `"hold_timer" in obj`, or uses `get_nodes_in_group`.
- Reorganizing scene node hierarchies for RV, player, equipment, or wheels.
- Introducing new interactables (props/equipment/enemies) that should participate in existing flows.

## 3. Canonical Workflow
1. Confirm target object contract from caller side (what methods/properties/groups are expected).
2. Verify callee scene/script actually provides those methods/properties at runtime.
3. Confirm group registration occurs in `_ready()` before dependent systems query groups.
4. Run manual in-scene interaction checks in `res://world/test_world.tscn`.

## 4. Commands/APIs/Procedures
- Primary run command:
  - `godot --path . res://world/test_world.tscn`
- Core contract APIs:
  - Player interaction target methods: `interact(player)`, `interact_hold(player)`, optional `install_wheel()`.
  - Hold contract field: mutable `hold_timer` property on target object.
  - RV resource contract: `add_item`, `has_materials`, `deduct_materials`, `get_all_items`, signal `inventory_changed`.
  - Placement contract: `start_placement`, `confirm_placement`, `cancel_placement`, `get_half_extents`, `get_bottom_face_correction`.
- Required groups in current codebase:
  - `player`, `monsters`, `rv`, `chassis`, `crafting_stations`.

## 5. Edge Cases and Failure Patterns
- Target has `interact_hold` but no `hold_timer`: hold flow never completes.
- Wheel hitbox parent chain changes: `_get_chassis()` cannot find chassis and wheel removal silently fails.
- Device expected under RV is placed on ground: `get_connected_rv()` returns null and system appears offline.
- Scene has missing or renamed player child nodes (`CollisionShape3D`, `Camera3D`): driver seat enter/exit breaks.

## 6. Validation Checklist
- [ ] Every new interactable supports the exact methods/properties expected by `player_interact.gd`.
- [ ] Any system using group lookup is added to the correct group in `_ready()`.
- [ ] RV-dependent devices are descendants of a node in group `rv`.
- [ ] Hold interactions, quick interactions, and fallback paths are manually verified in `test_world`.

## 7. Related Modules
- `docs/module/player-and-interaction.md`
- `docs/module/rv-and-equipment.md`
- `docs/module/enemy-ai-and-combat.md`

## 8. Source Files Used
- `player/player_interact.gd`
- `player/player.gd`
- `equipment/equipment.gd`
- `equipment/driver_seat.gd`
- `equipment/tablet_ui.gd`
- `equipment/scrapper.gd`
- `rv/chassis.gd`
- `rv/wheel_hitbox.gd`
- `enemies/monster.gd`

## 9. Completeness Notes
- This doc covers runtime integration contracts currently implemented in gameplay scripts.
- It does not define future multiplayer/networking contracts because no code evidence exists yet.
