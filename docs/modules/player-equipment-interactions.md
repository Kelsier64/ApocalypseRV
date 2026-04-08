# Module: Player Equipment Interactions

## Responsibility
This module defines the runtime contracts that connect player interaction input, carry inventory, equipment placement lifecycle, climb-state interaction hooks, and tablet crafting delegation to RV-connected stations. [Evidence: player/player_interact.gd:8, player/player.gd:76, player/player.gd:185, player/player.gd:488, equipment/tablet_ui.gd:126, equipment/crafting_station.gd:11]

Detailed walkthroughs, edge-case behavior sequences, and validation status live in `docs/design/player-interaction-and-equipment.md`.

## Boundaries
In scope:
1. Player inventory/carry API and placement entrypoints. [Evidence: player/player.gd:76, player/player.gd:165, player/player.gd:185]
2. Raycast-driven interaction timing for quick interact, hold interact, wheel install, and placement start. [Evidence: player/player_interact.gd:8, player/player_interact.gd:18, player/player_interact.gd:29, player/player_interact.gd:57]
3. Equipment placement lifecycle contract (`start_placement`, `confirm_placement`, `cancel_placement`). [Evidence: equipment/equipment.gd:84, equipment/equipment.gd:119, equipment/equipment.gd:149]
4. Tablet craft gating and station delegation contract. [Evidence: equipment/tablet_ui.gd:116, equipment/tablet_ui.gd:126, equipment/tablet_ui.gd:153]
5. Player climbing state hooks relevant to interaction-state transitions. [Evidence: player/player.gd:488, player/player.gd:570, player/player.gd:647]

Out of scope:
1. RV internals beyond consumed methods/signals. [Evidence: equipment/equipment.gd:64, equipment/tablet_ui.gd:99, equipment/tablet_ui.gd:153]
2. Scene-level UI open trigger orchestration outside tablet `on_open`. [Evidence: equipment/tablet_ui.gd:30]
3. Vehicle driving, world generation, and enemy combat implementations.

## Entry points
1. `player/player_interact.gd::_physics_process(_delta)` for frame-level interaction intent resolution. [Evidence: player/player_interact.gd:8]
2. `props/interactable_item.gd::interact(player)` as world-to-inventory ingestion point. [Evidence: props/interactable_item.gd:16, props/interactable_item.gd:22]
3. `player/player.gd::_unhandled_input(event)` for slot switching, drop, and placement controls. [Evidence: player/player.gd:233, player/player.gd:267, player/player.gd:273, player/player.gd:301]
4. `equipment/equipment.gd::start_placement(player)` and finalize/cancel methods for placement state transitions. [Evidence: equipment/equipment.gd:84, equipment/equipment.gd:119, equipment/equipment.gd:149]
5. `equipment/tablet_ui.gd::on_open()` and `_craft_item(recipe_name)` for craft UI activation and craft dispatch. [Evidence: equipment/tablet_ui.gd:30, equipment/tablet_ui.gd:126]
6. `player/player.gd::_try_start_climb()`, `_process_climbing(delta)`, `_abort_climb(reason)` for climb-state transition contract. [Evidence: player/player.gd:488, player/player.gd:570, player/player.gd:647]

## Data and interface contracts
1. Inventory item payload contract is `{ name, is_large, scene_path }` and capacity is 6 slots. [Evidence: player/player.gd:30, player/player.gd:76]
2. Interactable object contract:
   - Quick interaction: `interact(player)`.
   - Hold interaction: `interact_hold(player)` plus mutable `hold_timer`.
   - Wheel targets may expose `install_wheel()`.
   [Evidence: player/player_interact.gd:18, player/player_interact.gd:30, player/player_interact.gd:34, player/player_interact.gd:49]
3. Equipment contract:
   - `start_placement(player)` sets temporary ghost/placement state.
   - `confirm_placement(transform, parent)` finalizes transform/parent and collision exceptions.
   - `cancel_placement()` restores original parent/local state.
   [Evidence: equipment/equipment.gd:84, equipment/equipment.gd:119, equipment/equipment.gd:149]
4. RV duck-typed dependency contract used in this module includes `add_item`, `deduct_materials`, `consume_power`, `has_materials`, `has_usable_power`, and RV inventory/fuel/power signals where present. [Evidence: equipment/equipment.gd:67, equipment/tablet_ui.gd:99, equipment/tablet_ui.gd:121, equipment/tablet_ui.gd:124, equipment/tablet_ui.gd:153]
5. Crafting station contract requires group membership `crafting_stations` and `spawn_item(scene_path)` callable from tablet UI. [Evidence: equipment/crafting_station.gd:9, equipment/crafting_station.gd:11, equipment/tablet_ui.gd:138, equipment/tablet_ui.gd:153]
6. Climb contract currently exposed to tests includes `_try_start_climb`, `_process_climbing`, `_abort_climb`, `_build_climb_motion`, `_compute_rv_position_delta`, and `_sanitize_velocity_after_climb`; legacy mantle helper APIs are expected absent. [Evidence: player/player.gd:358, player/player.gd:322, player/player.gd:325, player/player.gd:488, player/player.gd:570, player/player.gd:647, tests/test_player_climbing.gd:118, tests/test_player_climbing.gd:120, tests/test_player_climbing.gd:121, tests/test_player_climbing_runtime.gd:21, tests/test_player_climbing_runtime.gd:24]

## Failure surface
1. Runtime break risk exists when RV method/signal names drift from duck-typed expectations. [Evidence: equipment/equipment.gd:67, equipment/tablet_ui.gd:99, equipment/tablet_ui.gd:121]
2. Craft request fails when no connected RV/station/power/materials or output scene cannot load. [Evidence: equipment/tablet_ui.gd:128, equipment/tablet_ui.gd:134, equipment/tablet_ui.gd:138, equipment/tablet_ui.gd:145, equipment/crafting_station.gd:20, equipment/crafting_station.gd:25]
3. Current climb contract tests are split: runtime test passes for mantle-removal/abort API, while `test_player_climbing.gd` still requires `_can_begin_climb(...)` helper that is not in current `player.gd`. [Evidence: tests/test_player_climbing_runtime.gd:18, tests/test_player_climbing_runtime.gd:21, tests/test_player_climbing.gd:32]

## Source files used
1. player/player.gd
2. player/player_interact.gd
3. equipment/equipment.gd
4. equipment/tablet_ui.gd
5. equipment/crafting_station.gd
6. props/interactable_item.gd
7. tests/test_player_climbing.gd
8. tests/test_player_climbing_runtime.gd
