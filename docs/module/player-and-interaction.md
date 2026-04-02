# Module: Player and Interaction

## 1. Responsibility
- Own first-person movement/camera, inventory handling, equipment placement mode, health/death lifecycle, and UI mode switching.
- Route world interactions through forward raycast logic (pickup, hold interactions, wheel install, placement initiation).

## 2. Boundaries and Dependencies
- Boundaries:
  - Does not implement RV physics or world generation.
  - Does not own crafting logic internals beyond opening tablet UI and invoking equipment contracts.
- Dependencies:
  - Scene children: `Camera3D`, `CollisionShape3D`, `InteractRay`, `InventoryUI`, `HealthBarUI`.
  - Contracts on targets: `interact`, `interact_hold`, `install_wheel`, `hold_timer`.
  - Equipment APIs for placement and geometry helpers.

## 3. Entry Points and Public Surface
- Player public methods used by other systems:
  - `add_item(item_name, is_large, scene_path) -> bool`
  - `is_placing_equipment() -> bool`
  - `get_active_item_name() -> String`
  - `consume_active_item() -> void`
  - `enter_equipment_placement(equip)`, `enter_ui_mode()`, `exit_ui_mode()`
  - `take_damage(amount)`
- Interaction ray entrypoint:
  - `PlayerInteract._physics_process(_delta)` runs interaction state machine each frame.

## 4. Internal Structure
| Part | Role | Key Symbols | File |
|---|---|---|---|
| Player controller | Movement, inventory, placement, health | `SPEED`, `MAX_SLOTS`, `placement_mode`, `take_damage` | `player/player.gd` |
| Interaction ray | Input-driven target interaction logic | `_install_timer`, `_e_was_pressed`, hold/quick flow | `player/player_interact.gd` |
| Inventory HUD | Slot panel rendering and active highlight | `update_slots` | `player/inventory_ui.gd` |
| Health HUD | HP bar and damage flash overlay | `set_health` | `player/health_bar_ui.gd` |
| Scene composition | Wires nodes/scripts and ray collision mask | `InteractRay` (mask `3`) | `player/player.tscn` |

## 5. Control Flow
### Main flow
1. `_ready()` captures mouse, sets camera active, initializes UI, adds player to `player` group.
2. `_unhandled_input` processes look, slot switching, drop, and placement confirmation/cancel.
3. `_physics_process` applies gravity/movement and updates equipment ghost placement if active.
4. `player_interact` ray loop processes E/F interaction paths based on target methods/properties.

### Error flow
1. If inventory full or large-item rule blocks add/switch, action is rejected with log output.
2. If held item scene path fails to load, equip/drop silently skips instantiation.
3. If placement ray has no hit, `can_place_equipment` is false and ghost hides.

## 6. Data Contracts
- Inventory item schema (dictionary):
  - `name: String`
  - `is_large: bool`
  - `scene_path: String`
- Placement contract assumptions:
  - `placing_equipment` supports confirm/cancel and geometry helper methods.
  - Placement parent search treats first ancestor matching `VehicleBody3D` or group `rv` as preferred attach target.
- Health contract for enemies:
  - `take_damage(float)` exists and handles cooldown/death internally.

## 7. Configuration Touchpoints
- Uses default gravity from `ProjectSettings` (`physics/3d/default_gravity`).
- Mouse sensitivity and movement constants are local script constants (`MOUSE_SENSITIVITY`, `SPEED`, `JUMP_VELOCITY`).
- Interaction ray uses fixed reach (`target_position`/ray query near 3-4m depending path).

## 8. Failure Modes and Safeguards
- Safeguards:
  - Damage cooldown prevents rapid repeated damage.
  - Interaction timers reset when not actively holding.
  - UI mode early-return blocks movement/look while tablet is open.
- Failure modes:
  - `set_physics_process(false)` cooldown in interaction script can feel unresponsive during rapid actions.
  - Fixed node names in dependent scripts (e.g., driver seat) can break if player scene hierarchy changes.
  - Active slot cycling across 0-5 can target empty slots when inventory has fewer items.

## 9. Testing and Verification
- Existing tests: none in repository.
- Missing tests:
  - Interaction timing transitions (quick tap vs hold trigger).
  - Large-item lock and slot switching behavior.
  - Placement confirm/cancel against RV vs world surfaces.
- Quick verification commands:
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
- `player/player.tscn`
- `world/test_world.tscn`

## 12. Completeness Notes
- Covers the current single-player control and interaction architecture.
- Multiplayer input arbitration and network ownership are not covered because no implementation evidence exists.
