# Module: Player Equipment Interactions

## Responsibility
This module coordinates first-person interaction timing, personal inventory state, equipment placement lifecycle, and tablet-driven crafting requests that resolve through RV-connected crafting stations. [Evidence: player/player_interact.gd:8, player/player.gd:37, player/player.gd:139, equipment/tablet_ui.gd:126, equipment/crafting_station.gd:11]

## Boundaries
In scope:
1. Player carry-slot state and held-item visuals. [Evidence: player/player.gd:12, player/player.gd:76]
2. Raycast interaction timing and key-driven control paths for E/F interactions. [Evidence: player/player_interact.gd:12, player/player_interact.gd:29, player/player_interact.gd:57]
3. Equipment placement start/confirm/cancel lifecycle. [Evidence: equipment/equipment.gd:73, equipment/equipment.gd:108, equipment/equipment.gd:138]
4. Craft UI recipe gating and crafting dispatch to connected stations. [Evidence: equipment/tablet_ui.gd:8, equipment/tablet_ui.gd:116, equipment/tablet_ui.gd:153]

Out of scope:
1. RV implementation details for inventory, materials, fuel, and power storage internals (only consumed via method/signal contracts). [Evidence: equipment/equipment.gd:57, equipment/tablet_ui.gd:99, equipment/tablet_ui.gd:153]
2. Scene-specific UI opening triggers and broader world interaction orchestration not present in these files. [Evidence: equipment/tablet_ui.gd:30, equipment/tablet_ui.gd:83]
3. Vehicle driving, enemy combat logic, and non-partition systems. [Evidence: GDD.md:19, GDD.md:85]

## Entry points
1. `player/player_interact.gd::_physics_process(_delta)` handles per-frame interaction intent resolution. [Evidence: player/player_interact.gd:8]
2. `props/interactable_item.gd::interact(player)` injects pickup payload into player inventory. [Evidence: props/interactable_item.gd:16, props/interactable_item.gd:22]
3. `equipment/equipment.gd::start_placement(player)` begins ghost placement mode. [Evidence: equipment/equipment.gd:73, equipment/equipment.gd:90]
4. `player/player.gd::_unhandled_input(event)` handles slot changes, drop, and placement confirm/cancel/toggle controls. [Evidence: player/player.gd:187, player/player.gd:201, player/player.gd:215, player/player.gd:219]
5. `equipment/tablet_ui.gd::on_open()` initializes connection/state and refreshes craft availability. [Evidence: equipment/tablet_ui.gd:30, equipment/tablet_ui.gd:46, equipment/tablet_ui.gd:47]
6. `equipment/tablet_ui.gd::_craft_item(recipe_name)` executes crafting gate checks and delegates spawn. [Evidence: equipment/tablet_ui.gd:126, equipment/tablet_ui.gd:138, equipment/tablet_ui.gd:153]

## Internal structure table
| Component | Type | Purpose | Key state/functions | Evidence |
|---|---|---|---|---|
| Player core | `CharacterBody3D` script | Owns inventory, active slot, held visuals, placement preview, and drop behavior | `inventory`, `active_slot_index`, `add_item`, `_equip_active_slot`, `drop_item` | player/player.gd:13; player/player.gd:15; player/player.gd:37; player/player.gd:76; player/player.gd:151 |
| Interaction driver | `RayCast3D` script | Converts key holds/releases into wheel install, interact, interact_hold, and equipment placement starts | `_install_timer`, `_physics_process`, E/F logic | player/player_interact.gd:6; player/player_interact.gd:8; player/player_interact.gd:16; player/player_interact.gd:56 |
| Prop pickup | `RigidBody3D` script (`Prop`) | Supplies item metadata and scene path to player inventory on interact | `item_name`, `is_large`, `interact` | props/interactable_item.gd:4; props/interactable_item.gd:5; props/interactable_item.gd:16 |
| Equipment base | `RigidBody3D` script (`Equipment`) | Handles ghost state, RV connection lookup, placement finalize/cancel, and collision exception safety | `hold_timer`, `start_placement`, `confirm_placement`, `cancel_placement` | equipment/equipment.gd:43; equipment/equipment.gd:73; equipment/equipment.gd:108; equipment/equipment.gd:138 |
| Tablet UI | `CanvasLayer` script | Presents RV status and recipes, enables/disables crafting, dispatches craft requests | `recipes`, `connected_rv`, `on_open`, `_evaluate_craft_buttons`, `_craft_item` | equipment/tablet_ui.gd:8; equipment/tablet_ui.gd:19; equipment/tablet_ui.gd:30; equipment/tablet_ui.gd:116; equipment/tablet_ui.gd:126 |
| Crafting station | `Equipment` subclass | Validates RV/power, loads crafted scene, spawns output in world | `power_cost_per_spawn`, `spawn_item`, group registration | equipment/crafting_station.gd:5; equipment/crafting_station.gd:11; equipment/crafting_station.gd:9 |

## Control flow
1. Quick pickup flow
   - Raycast sees collider and E press; if object supports `interact`, call once and debounce. [Evidence: player/player_interact.gd:29, player/player_interact.gd:36, player/player_interact.gd:38]
   - Prop sends `(item_name, is_large, scene_path)` into player `add_item`; on success prop despawns. [Evidence: props/interactable_item.gd:22, props/interactable_item.gd:25, player/player.gd:37]
2. Hold interaction flow
   - E hold increments target `hold_timer`; at 1.0 seconds executes `interact_hold(player)`. [Evidence: player/player_interact.gd:30, player/player_interact.gd:33, player/player_interact.gd:34]
   - Early release routes to quick `interact(player)` when `hold_timer` was partially accumulated. [Evidence: player/player_interact.gd:44, player/player_interact.gd:46, player/player_interact.gd:49]
3. Wheel install flow
   - Requires active item name equal to `Wheel`, collider with `install_wheel`, and E hold for 1.0 seconds. [Evidence: player/player_interact.gd:17, player/player_interact.gd:18, player/player_interact.gd:21]
   - Successful install consumes active inventory item. [Evidence: player/player_interact.gd:22, player/player_interact.gd:23]
4. Equipment placement flow
   - F hold for 2.0 seconds on Equipment calls `start_placement`. [Evidence: player/player_interact.gd:57, player/player_interact.gd:61, player/player_interact.gd:62]
   - Player preview updates in physics step from ray hit, choosing orientation mode and offset. [Evidence: player/player.gd:297, player/player.gd:323, player/player.gd:361, player/player.gd:368]
   - Input confirms with LMB and valid hit, cancels with RMB, toggles mode with R. [Evidence: player/player.gd:221, player/player.gd:227, player/player.gd:252, player/player.gd:255, player/player.gd:256]
5. Craft flow
   - Tablet open resolves connected RV and binds live inventory/fuel/power signals. [Evidence: equipment/tablet_ui.gd:33, equipment/tablet_ui.gd:39, equipment/tablet_ui.gd:106, equipment/tablet_ui.gd:109]
   - Craft press checks RV power/materials and requires a station in `crafting_stations` tied to same RV. [Evidence: equipment/tablet_ui.gd:128, equipment/tablet_ui.gd:134, equipment/tablet_ui.gd:138, equipment/tablet_ui.gd:145]
   - On material deduction success, station spawns item and consumes per-output power. [Evidence: equipment/tablet_ui.gd:153, equipment/crafting_station.gd:25, equipment/crafting_station.gd:35]
6. RV climbing flow
   - Trigger requires hold W + valid RV wall probe hit; jump is optional, while wall-normal and hit-height gates are required to reject undercarriage/invalid wall contacts.
   - Manual detach is explicit: pressing S or Space (`ui_accept`) while in climbing state immediately exits climb to normal locomotion.
   - Climbing and mantling states apply RV transform-delta compensation each frame to reduce moving-platform desync and launch risk.
   - Top-out starts only when top probe surface, stand support ray + headroom ray checks, and forward-clear gate all pass; support depth is derived from mantle clearance (`max(MANTLE_MIN_TARGET_CLEARANCE, MANTLE_UP_OFFSET + stand-offset) + 0.2`) to avoid false negatives near roof edges.
   - Lost-wall handling is deferred: on contact loss, climb attempts mantle immediately, then runs grace countdown (`CLIMB_CONTACT_GRACE_TIME = 0.28`), and performs a final mantle retry before `_abort_climb("lost wall contact")`.

## Data contracts
1. Player inventory entry contract
   - Shape: `{ "name": String, "is_large": bool, "scene_path": String }`. [Evidence: player/player.gd:45]
   - Constraints: max 6 slots; only one concurrently carried large item. [Evidence: player/player.gd:12, player/player.gd:38, player/player.gd:41]
2. Prop pickup contract
   - Producer fields: `item_name`, `is_large`, and `scene_file_path` fallback resolution. [Evidence: props/interactable_item.gd:4, props/interactable_item.gd:5, props/interactable_item.gd:18, props/interactable_item.gd:20]
3. Equipment placement contract
   - Placement candidate stores original local/parent state for cancellation restore. [Evidence: equipment/equipment.gd:78, equipment/equipment.gd:79, equipment/equipment.gd:146]
   - Parenting contract allows RV/root fallback via player ray hit path. [Evidence: player/player.gd:240, player/player.gd:243, player/player.gd:250]
4. Crafting recipe contract
   - Recipe map key -> `{ scene: String, costs: Dictionary<String,int> }`. [Evidence: equipment/tablet_ui.gd:8, equipment/tablet_ui.gd:10, equipment/tablet_ui.gd:11]
5. RV dependency contract (duck-typed)
   - Methods/signals expected by this module include `has_materials`, `deduct_materials`, `has_usable_power`, `consume_power`, and inventory/fuel/power change signals. [Evidence: equipment/equipment.gd:57, equipment/equipment.gd:68, equipment/tablet_ui.gd:99, equipment/tablet_ui.gd:121, equipment/tablet_ui.gd:124, equipment/tablet_ui.gd:153]

## Config touchpoints
1. Input and key mappings in this module
   - E/F/G/R and number keys 1-6 are hardcoded checks in scripts. [Evidence: player/player_interact.gd:12, player/player_interact.gd:57, player/player.gd:210, player/player.gd:215, player/player.gd:221]
2. Inventory and placement tuning
   - `MAX_SLOTS = 6`, `max_place_distance = 4.0`, placement modes `SURFACE` and `UPRIGHT`. [Evidence: player/player.gd:12, player/player.gd:20, player/player.gd:22]
3. Timing thresholds
   - Install/hold interaction uses 1.0s, placement start uses 2.0s, pickup debounce uses 0.5s wait. [Evidence: player/player_interact.gd:21, player/player_interact.gd:33, player/player_interact.gd:39, player/player_interact.gd:61]
4. Crafting costs and power
   - Tablet recipe costs and station `power_cost_per_spawn` are script-side constants/exports. [Evidence: equipment/tablet_ui.gd:12, equipment/tablet_ui.gd:13, equipment/crafting_station.gd:5]
5. Climbing thresholds
   - Wall-normal gate, hit-height window, contact grace duration (`0.28s`), RV angular speed ceiling, and mantle duration are script constants tuned for stability. [Evidence: player/player.gd:5, player/player.gd:7, player/player.gd:14, player/player.gd:15, player/player.gd:17]

## Failure modes
1. Pickup rejected due to capacity/large-item constraints. [Evidence: player/player.gd:38, player/player.gd:41]
2. Placement cannot confirm if raycast has no valid hit (`can_place_equipment` false). [Evidence: player/player.gd:227, player/player.gd:370]
3. Crafted output blocked by missing RV, no usable power, insufficient materials, no station, wrong-station RV, or load failure. [Evidence: equipment/tablet_ui.gd:127, equipment/tablet_ui.gd:129, equipment/tablet_ui.gd:134, equipment/tablet_ui.gd:139, equipment/tablet_ui.gd:149, equipment/crafting_station.gd:22]
4. Module relies on duck-typed RV methods/signals; interface drift can break functionality at runtime. [Evidence: equipment/equipment.gd:57, equipment/tablet_ui.gd:109, equipment/tablet_ui.gd:121]
5. Climbing can intentionally abort when RV angular speed is too high or wall contact grace expires, but only after the runtime performs final mantle retries; this reduces top-edge drop-loop behavior before transitioning back to normal locomotion. [Evidence: player/player.gd:579, player/player.gd:602, player/player.gd:629, player/player.gd:634]

## Testing
1. Interaction regression matrix
   - Verify E quick tap, E hold, E early release, and F hold transitions with one collider target at a time. [Evidence: player/player_interact.gd:28, player/player_interact.gd:44, player/player_interact.gd:56]
2. Inventory behavior tests
   - Validate slot cycling, large-item lock, drop path, and consume path effects on UI and held model. [Evidence: player/player.gd:64, player/player.gd:67, player/player.gd:151, player/player.gd:127, player/player.gd:136]
3. Placement stability tests
   - Confirm RV-parent selection and collision exceptions prevent unstable parent collisions after placement. [Evidence: player/player.gd:243, equipment/equipment.gd:123, equipment/equipment.gd:129]
4. Craft integration tests
   - Open tablet, observe disabled/enabled craft states under power/material toggles, then validate spawned output location and power deduction behavior. [Evidence: equipment/tablet_ui.gd:116, equipment/tablet_ui.gd:121, equipment/tablet_ui.gd:153, equipment/crafting_station.gd:25, equipment/crafting_station.gd:37]
5. Climbing tests
   - Run `tests/test_player_climbing.gd` to validate wall trigger gates, undercarriage rejection, strict mantle gate checks, RV-delta compensation math, and climb exit velocity sanitization.
   - Run `tests/test_player_climbing_runtime.gd` to validate runtime-facing climb contracts (`_abort_climb`, `_compute_mantle_target`) and deterministic top-out clearance.

## Change checklist
1. If you change inventory item shape, update all producers/consumers (`Prop.interact`, player equip/drop/consume paths). [Evidence: props/interactable_item.gd:22, player/player.gd:45, player/player.gd:90, player/player.gd:130, player/player.gd:153]
2. If you change interaction timings, update both behavior docs and player interaction script constants/threshold checks. [Evidence: player/player_interact.gd:21, player/player_interact.gd:33, player/player_interact.gd:61]
3. If you add recipes, ensure UI setup, craft button evaluation, and station spawn constraints still hold. [Evidence: equipment/tablet_ui.gd:58, equipment/tablet_ui.gd:116, equipment/tablet_ui.gd:138]
4. If RV API/signals change, update duck-typed checks and reconnection logic in Equipment/Tablet UI. [Evidence: equipment/equipment.gd:57, equipment/tablet_ui.gd:96, equipment/tablet_ui.gd:106]
5. If placement parenting rules change, retest collision exception behavior for RV ancestors. [Evidence: player/player.gd:237, equipment/equipment.gd:126, equipment/equipment.gd:129]
6. If climbing constants or probe setup change, re-run `tests/test_player_climbing.gd` and `tests/test_player_climbing_runtime.gd`, then manually verify W-based climbing on parked and moving RV.

## Source Files Used
1. player/player.gd
2. player/player_interact.gd
3. equipment/equipment.gd
4. equipment/tablet_ui.gd
5. equipment/crafting_station.gd
6. props/interactable_item.gd
7. GDD.md

## Completeness notes
1. This module doc covers only player inventory/interactions plus equipment placement/crafting UI partition requested for initialization. [Evidence: player/player.gd:12, equipment/tablet_ui.gd:126, GDD.md:55, GDD.md:64]
2. Assumption: wheel installation target contract (`install_wheel`) is defined elsewhere and remains compatible with active-item consumption flow. [Evidence: player/player_interact.gd:18, player/player_interact.gd:23]
3. Unknown: full RV class typing, network/multiplayer synchronization, and authoritative ownership model are outside provided evidence. [Evidence: equipment/equipment.gd:57, equipment/tablet_ui.gd:33]
4. Unknown: UX-level prompts/progress indicators for hold actions are not specified in this partition. [Evidence: player/player_interact.gd:19, player/player_interact.gd:59]
