# Module: Player and Interaction

## 1. Responsibility
This module handles first-person character control, inventory and held-item behavior, interaction raycast logic, equipment placement mode, and player health feedback.

## 2. Boundaries and Dependencies
- Owns player-local state such as inventory slots, active item, health, and placement mode.
- Delegates item-specific behavior to interactable objects via duck-typed methods.
- Depends on camera child structure and raycast collider contracts.
- Integrates with equipment, RV wheel installation, and monster damage APIs.

## 3. Entry Points and Public Surface
- Player core methods:
  - `add_item(item_name, is_large, scene_path) -> bool`
  - `drop_item()`
  - `consume_active_item()`
  - `take_damage(amount)`
  - `enter_equipment_placement(equip)`
  - `is_placing_equipment() -> bool`
  - `get_active_item_name() -> String`
- Interaction entrypoint:
  - `PlayerInteract._physics_process(delta)` handles E/F hold rules and quick interactions.

## 4. Internal Structure
| Part | Role | Key Symbols | File |
|---|---|---|---|
| Character controller | Movement, camera look, slot switching, placement update | `_unhandled_input`, `_physics_process` | `player/player.gd` |
| Interaction raycast | Timed E/F actions, hold-release logic, wheel install checks | `_physics_process`, `_install_timer`, `_e_was_pressed` | `player/player_interact.gd` |
| Inventory UI | Slot labels and active slot highlight | `update_slots` | `player/inventory_ui.gd` |
| Health UI | Health bar and damage flash effect | `set_health`, `flash_damage` | `player/health_bar_ui.gd` |
| Interactable prop base | Generic pickup behavior and held transforms | `interact(player)` | `props/interactable_item.gd` |

## 5. Control Flow
### Main flow
1. Player script initializes camera, UI, and group membership.
2. Input updates movement, slot selection, dropping, and placement confirmation/cancel.
3. Interaction raycast checks current collider.
4. E interactions:
   - hold for `interact_hold` paths,
   - quick release for `interact` paths,
   - special wheel install path when active item is wheel.
5. F hold triggers equipment placement after 2 seconds.
6. UI refreshes inventory and health states on state changes.

### Error flow
1. Inventory full or large-item conflicts reject pickup.
2. Missing scene on equip/drop load skips visual instantiation.
3. If no collider or contract mismatch (`has_method` false), interaction exits safely.
4. Damage during death state is ignored by early return checks.

## 6. Data Contracts
- Inventory entry structure: `{ "name": String, "is_large": bool, "scene_path": String }`.
- Interactable object contract:
  - quick interaction: `interact(player)`.
  - hold interaction: `interact_hold(player)` with mutable `hold_timer`.
- Wheel install target contract: `install_wheel() -> bool`.
- Equipment contract: object is `Equipment` and supports placement methods.

## 7. Configuration Touchpoints
- `player/player.gd` constants: movement speed, jump, mouse sensitivity, max slots.
- Placement configuration: `max_place_distance`, placement mode enum.
- Health configuration: `max_player_health`, cooldown timers.

## 8. Failure Modes and Safeguards
- Slot lock while carrying large item avoids inconsistent hand state.
- Raycast interaction includes short cooldown pause to prevent rapid repeat activation.
- Placement flow ignores collisions with player/equipment during raycast.
- UI updates guarded with `has_method` checks.

## 9. Testing and Verification
Existing tests:
- No dedicated automated tests for player interaction scripts.

Missing tests:
- E key hold/release timing behavior.
- Wheel installation and inventory consumption integration.
- Placement confirm/cancel parent reassignment behavior.
- Health cooldown and respawn sequence.

Quick verification commands:
- `godot --path . res://world/test_world.tscn`

## 10. Change Checklist
- [ ] API contract checked
- [ ] Backward compatibility checked
- [ ] Docs consistency checked
- [ ] Tests updated or justified

## 11. Source Files Used
- `player/player.gd`
- `player/player_interact.gd`
- `player/inventory_ui.gd`
- `player/health_bar_ui.gd`
- `props/interactable_item.gd`
- `props/wheel.gd`

## 12. Completeness Notes
This module doc captures the current single-player interaction model and item workflow. It does not define future multiplayer authority or input-remapping architecture.