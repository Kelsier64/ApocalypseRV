# Player Traversal and Interaction Module Contract

## Module Purpose
This module governs first-person traversal, climb-state transitions, inventory ownership, and player-side interaction entry points.

Implementation references:
- Core script: [player/player.gd](../../player/player.gd)
- Interaction raycast adapter: [player/player_interact.gd](../../player/player_interact.gd#L1)
- Prop pickup counterpart: [props/interactable_item.gd](../../props/interactable_item.gd#L1)

Detailed behavior walk-throughs:
- Climb and combat flow: [docs/design/climbing-and-combat-behavior.md](../design/climbing-and-combat-behavior.md)
- Interaction timing and pickup flow: [docs/design/player-interaction-flow.md](../design/player-interaction-flow.md)

## Module Boundaries
- `PlayerInventory` owns capacity, large-item restrictions, slot selection, and consumption without scene dependencies.
- `EquipmentPlacement` owns preview state, orientation, and confirm/cancel input. `player.gd` authorizes entry via its mode helpers and passes its scene context to placement updates.
- `player.gd` retains movement, mode transitions, health, and held-item presentation. External callers use `add_item`, `get_active_item_name`, and `consume_active_item` rather than modifying inventory fields.
- Validate with `tests/test_player_inventory.gd` and `tests/test_equipment_lifecycle.gd`, alongside the climbing suites.

## State and Data Contracts
- Locomotion states are NORMAL and CLIMBING.
- Inventory slot ceiling is fixed at 6 entries.
- PlayerInventory owns items and active-slot selection; it derives the large-item limit from item data.

Evidence:
- Locomotion enum/state: [player/player.gd](../../player/player.gd), [player/player.gd](../../player/player.gd)
- Max slots: [player/player.gd](../../player/player.gd)
- Inventory rules: [player/player_inventory.gd](../../player/player_inventory.gd)

## Inventory API Contract

### add_item(item_name, is_large, scene_path) -> bool
Expected behavior:
- Rejects adding large item when already carrying one.
- Rejects add when inventory is full.
- Adds item metadata and updates equipped slot display on success.

Evidence:
- Method and rejection gates: [player/player.gd](../../player/player.gd), [player/player.gd](../../player/player.gd), [player/player.gd](../../player/player.gd)

### get_active_item_name() -> String
Expected behavior:
- Returns current slot name or empty string when slot is invalid.

Evidence:
- Method body: [player/player.gd](../../player/player.gd)

### consume_active_item() -> void
Expected behavior:
- Removes currently active slot item.
- Clears large-item ownership when consuming a large item.
- Re-clamps active slot index and refreshes equipped visuals.

Evidence:
- Method and large-item clear: [player/player.gd](../../player/player.gd), [player/player.gd](../../player/player.gd)

### drop_item() -> void
Expected behavior:
- Spawns active item scene into world in front of player.
- Removes item from inventory and updates visual state.

Evidence:
- Method and spawn/removal flow: [player/player.gd](../../player/player.gd), [player/player.gd](../../player/player.gd)

## Traversal and Climbing Contract

### Climb state transition surface
Expected helpers and behavior:
- _try_start_climb performs entry checks and transitions to CLIMBING.
- _process_climbing handles per-frame climb motion and abort conditions.
- _abort_climb exits climb and routes cleanup.
- `ClimbMath` carries attachment points through vehicle translation/rotation and verifies roof transfers with full-body sweeps. `RVSupport` tracks frozen RV floor panels during normal movement.

Evidence:
- Start/process/abort methods: [player/player.gd](../../player/player.gd), [player/player.gd](../../player/player.gd), [player/player.gd](../../player/player.gd)
- Utility methods: [player/player.gd](../../player/player.gd), [player/player.gd](../../player/player.gd)
- Test contract checks: [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L83), [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L97), [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L109)

### Collision policy by locomotion state
Expected behavior:
- Body collision remains enabled in NORMAL.
- Body collision remains enabled in CLIMBING; only seated mode disables the capsule.
- Detaching inherits vehicle motion; standing on a removed panel releases support.

Evidence:
- Collision helper and state gate: [player/player.gd](../../player/player.gd), [player/player.gd](../../player/player.gd)
- Test coverage: [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L73), [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L74)

### Climb geometry gate helpers
Expected behavior:
- _is_rv_wall_normal discriminates wall-like versus floor-like normals.
- _is_valid_climb_hit_height enforces valid contact height window.
- _build_climb_motion must not push inward into wall interior.

Evidence:
- Helper methods: [player/player.gd](../../player/player.gd), [player/player.gd](../../player/player.gd), [player/player.gd](../../player/player.gd)
- Test expectations: [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L50), [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L61), [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L125)

## Interaction Adapter Contract (player_interact)
Expected behavior:
- Runs per physics tick, resolves looked-at collider, and applies E/F hold semantics.
- Supports wheel installation branch and generic interact_hold/interact branches.
- Uses player.consume_active_item after successful wheel install.

Evidence:
- Adapter loop: [player/player_interact.gd](../../player/player_interact.gd#L8)
- Wheel install branch: [player/player_interact.gd](../../player/player_interact.gd#L21), [player/player_interact.gd](../../player/player_interact.gd#L22), [player/player_interact.gd](../../player/player_interact.gd#L23)
- Generic interact paths: [player/player_interact.gd](../../player/player_interact.gd#L30), [player/player_interact.gd](../../player/player_interact.gd#L37), [player/player_interact.gd](../../player/player_interact.gd#L49)

## External Pickup Contract (Prop)
Expected behavior:
- Prop.interact must call player.add_item when available.
- Prop despawns itself only after successful add_item.

Evidence:
- Prop contract: [props/interactable_item.gd](../../props/interactable_item.gd#L16), [props/interactable_item.gd](../../props/interactable_item.gd#L22), [props/interactable_item.gd](../../props/interactable_item.gd#L25)

## Test-Derived Contract Notes
- Mantle helper APIs are expected removed from player runtime contract.
- Climb state helper API surface remains test-validated.

Evidence:
- Mantle removal checks: [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L120), [tests/test_player_climbing_runtime.gd](../../tests/test_player_climbing_runtime.gd#L21)
- Climb helper checks: [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L118), [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L119)

## Assumptions and Unknowns
- tests/test_player_climbing.gd currently asserts _can_begin_climb exists, but player/player.gd does not define that helper in this snapshot. Contract ownership for that helper is unclear.
  Evidence: [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L32), [player/player.gd](../../player/player.gd)
- Interaction adapter references a concrete Equipment type in runtime branch logic, but interface/class guarantees for Equipment are outside this partition scope.
  Evidence: [player/player_interact.gd](../../player/player_interact.gd#L58)
