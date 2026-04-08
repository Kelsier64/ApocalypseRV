# Player Interaction and Equipment

## Scope
This document records runtime behavior for player interaction timing, inventory carry rules, equipment placement, climb interaction contracts, and tablet-driven crafting for the current code state. [Evidence: player/player_interact.gd:8, player/player.gd:30, player/player.gd:40, player/player.gd:488, equipment/tablet_ui.gd:126]

## Runtime context
The partition runs in the configured Godot 4.6 project with Jolt Physics and GL Compatibility renderer. [Evidence: project.godot:17, project.godot:27, project.godot:32]

## Inventory and pickup behavior
1. Player inventory is a 6-slot array of dictionaries (`name`, `is_large`, `scene_path`). [Evidence: player/player.gd:30, player/player.gd:31, player/player.gd:76]
2. `add_item` rejects pickup when inventory is full and rejects a second large item while one is already carried. [Evidence: player/player.gd:76, player/player.gd:80]
3. Slot switching is blocked when the currently active slot contains a large item and the target slot is different. [Evidence: player/player.gd:103]
4. Dropping the active item (G key path) respawns the item scene in front of the player and removes inventory state. [Evidence: player/player.gd:197, player/player.gd:233]
5. Prop pickup passes `item_name`, `is_large`, and scene path through `player.add_item(...)`; successful pickup queues the prop for deletion. [Evidence: props/interactable_item.gd:16, props/interactable_item.gd:22, props/interactable_item.gd:25]

## Interaction timing behavior
1. `player_interact.gd` drives interaction from one raycast update loop. [Evidence: player/player_interact.gd:8]
2. Wheel install path requires player holding `Wheel`, target exposing `install_wheel`, and E held for 1.0s. [Evidence: player/player_interact.gd:18, player/player_interact.gd:21, player/player_interact.gd:22]
3. General hold interaction requires E plus target `interact_hold` and `hold_timer`; at 1.0s it calls `interact_hold(player)`. [Evidence: player/player_interact.gd:29, player/player_interact.gd:30, player/player_interact.gd:34]
4. Releasing E before hold completion converts to quick interact (`interact(player)`) for hold-capable targets. [Evidence: player/player_interact.gd:44, player/player_interact.gd:49]
5. Quick interact path applies a 0.5s temporary physics-process pause to debounce repeated pickup triggers. [Evidence: player/player_interact.gd:39, player/player_interact.gd:51]

## Equipment placement behavior
1. F-hold placement entry requires E not pressed, collider is `Equipment`, player not already placing, and `hold_timer >= 2.0`. [Evidence: player/player_interact.gd:57, player/player_interact.gd:61]
2. Entering placement sets player placement state and resets mode to `SURFACE`. [Evidence: player/player.gd:185, player/player.gd:187]
3. `Equipment.start_placement` stores original transform/parent, freezes rigidbody in kinematic mode, and clears collision layer/mask while in ghost mode. [Evidence: equipment/equipment.gd:84, equipment/equipment.gd:94, equipment/equipment.gd:95, equipment/equipment.gd:96]
4. During placement preview, raycast hit drives `can_place_equipment`, orientation basis, and contact-face offset from equipment extents. [Evidence: player/player.gd:692, player/player.gd:705, player/player.gd:721, player/player.gd:757, player/player.gd:766]
5. Placement controls: R toggles `SURFACE/UPRIGHT`, LMB confirms only when `can_place_equipment` is true, RMB cancels. [Evidence: player/player.gd:267, player/player.gd:273, player/player.gd:301]
6. Confirm path reparents to RV ancestor when available, keeps equipment frozen/static, and adds collision exceptions up parent chain to prevent parent collisions. [Evidence: player/player.gd:298, equipment/equipment.gd:119, equipment/equipment.gd:132, equipment/equipment.gd:140]
7. Cancel path reparents back to original parent, restores local transform/materials, and returns static frozen physics settings. [Evidence: equipment/equipment.gd:149, equipment/equipment.gd:167, equipment/equipment.gd:169]

## Crafting interaction behavior
1. Tablet UI currently exposes one recipe (`Gasoline Can`) with material costs in script data. [Evidence: equipment/tablet_ui.gd:8]
2. `on_open` resolves current RV connection and rewires RV signals (`inventory_changed`, `fuel_changed`, `power_changed`) as connection changes. [Evidence: equipment/tablet_ui.gd:30, equipment/tablet_ui.gd:33, equipment/tablet_ui.gd:99, equipment/tablet_ui.gd:109]
3. Craft button state is disabled when RV is missing, when RV power is unusable, or when materials are insufficient for recipe costs. [Evidence: equipment/tablet_ui.gd:116, equipment/tablet_ui.gd:121, equipment/tablet_ui.gd:124]
4. Craft execution requires: connected RV, usable power, sufficient materials, at least one node in `crafting_stations`, and a station connected to the same RV. [Evidence: equipment/tablet_ui.gd:126, equipment/tablet_ui.gd:128, equipment/tablet_ui.gd:134, equipment/tablet_ui.gd:138, equipment/tablet_ui.gd:145]
5. On successful `deduct_materials`, tablet delegates spawn to station `spawn_item(scene_path)`. [Evidence: equipment/tablet_ui.gd:153]
6. `CraftingStation.spawn_item` enforces RV connectivity/power, loads scene, consumes output power, then spawns into world scene at `SpawnMarker` transform when present. [Evidence: equipment/crafting_station.gd:11, equipment/crafting_station.gd:16, equipment/crafting_station.gd:20, equipment/crafting_station.gd:25, equipment/crafting_station.gd:36, equipment/crafting_station.gd:37]

## Climbing interaction behavior
1. Climb start is attempted from normal locomotion when W is pressed and wall probe is colliding with an RV ancestor. [Evidence: player/player.gd:488, player/player.gd:495, player/player.gd:500]
2. Start gate checks include wall-normal gate, hit-height gate, and a ceiling-distance pre-check using `CLIMB_START_CEILING_CHECK_DISTANCE`. [Evidence: player/player.gd:305, player/player.gd:311, player/player.gd:509, player/player.gd:510]
3. While climbing, manual detach occurs immediately on S or `ui_accept` (Space by default). [Evidence: player/player.gd:575, player/player.gd:576, player/player.gd:577]
4. While climbing, RV angular-speed guard aborts climb when RV spin exceeds limit. [Evidence: player/player.gd:582]
5. Wall contact grace is refreshed on valid contact and otherwise counts down to lost-contact abort (`CLIMB_CONTACT_GRACE_TIME = 0.28`). [Evidence: player/player.gd:14, player/player.gd:598, player/player.gd:645]
6. Upward climb movement is ceiling-clamped; overhead hit during upward input triggers immediate abort (`ceiling detected`). [Evidence: player/player.gd:374, player/player.gd:615, player/player.gd:627]
7. RV delta compensation is applied each climb frame, and climb exit applies re-entry cooldown plus vertical-velocity sanitization. [Evidence: player/player.gd:558, player/player.gd:663, player/player.gd:668, player/player.gd:325]

## Validation status
1. `tests/test_player_climbing_runtime.gd` currently validates `_abort_climb` presence and confirms mantle helpers are removed. [Evidence: tests/test_player_climbing_runtime.gd:18, tests/test_player_climbing_runtime.gd:21, tests/test_player_climbing_runtime.gd:24]
2. `tests/test_player_climbing.gd` currently expects `_can_begin_climb(...)` to exist; current `player.gd` does not expose that helper, so this test fails unless contract or test is updated. [Evidence: tests/test_player_climbing.gd:32, tests/test_player_climbing.gd:34, tests/test_player_climbing.gd:35]

## Source files used
1. player/player.gd
2. player/player_interact.gd
3. equipment/equipment.gd
4. equipment/tablet_ui.gd
5. equipment/crafting_station.gd
6. props/interactable_item.gd
7. tests/test_player_climbing.gd
8. tests/test_player_climbing_runtime.gd
9. project.godot

## Assumptions and unknowns
1. Assumption: this partition documents script-level behavior only; RV internal implementation remains external and duck-typed from this scope. [Evidence: equipment/equipment.gd:64, equipment/tablet_ui.gd:121, equipment/tablet_ui.gd:153]
2. Unknown: exact in-world trigger path that opens tablet UI is outside this evidence set; only `on_open` behavior is in scope. [Evidence: equipment/tablet_ui.gd:30]
