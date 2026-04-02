# Module: RV and Equipment

## 1. Responsibility
- Provide the drivable RV chassis, wheel slot lifecycle, and shared material inventory.
- Provide reusable placement behavior for equipment and specialized machine/device behaviors (driver seat, scrapper, tablet, crafting station, RV panels).

## 2. Boundaries and Dependencies
- Boundaries:
  - Does not own player movement logic or world streaming decisions.
  - Does not directly implement enemy behaviors.
- Dependencies:
  - Godot `VehicleBody3D`, `VehicleWheel3D`, `RigidBody3D`, `StaticBody3D`.
  - Player-facing interaction and placement APIs.
  - Prop metadata and scenes for wheel and scrap inputs/outputs.

## 3. Entry Points and Public Surface
- RV (`Chassis`) public surface:
  - `set_driving_state(state)`
  - `install_wheel() -> bool`, `remove_wheel(slot_index)`, `get_installed_wheel_count()`
  - `add_item`, `has_materials`, `deduct_materials`, `get_item_count`, `get_all_items`
  - Signal: `inventory_changed(item_name, new_amount)`
- Equipment base/public methods:
  - `get_connected_rv()`
- `start_placement(player)`, `confirm_placement(new_global_transform, new_parent)`, `cancel_placement()`
  - `get_half_extents()`, `get_bottom_face_correction()`
- Device-specific entrypoints:
  - Driver seat: `interact_hold(player)`, `exit_seat()`
  - Scrapper: `recycle_prop(prop)`
  - Crafting station: `spawn_item(scene_path)`
  - Tablet UI: `on_open()`, `_craft_item(recipe_name)`

## 4. Internal Structure
| Part | Role | Key Symbols | File |
|---|---|---|---|
| Chassis vehicle core | Drive physics, steering, braking, inventory | `max_engine_force`, `inventory_changed`, `_physics_process` | `rv/chassis.gd` |
| Wheel removal hitbox | Hold-interact wheel detach and wheel prop spawn | `interact_hold`, `_get_chassis` | `rv/wheel_hitbox.gd` |
| Equipment base | Placement lifecycle and RV ancestry lookup | `start_placement`, `confirm_placement`, `get_connected_rv` | `equipment/equipment.gd` |
| Driver seat | Board/exit flow and camera switching | `current_driver`, `interact_hold`, `exit_seat` | `equipment/driver_seat.gd` |
| Scrapper | Timed prop crushing and material conversion | `props_being_crushed`, `_finish_recycle` | `equipment/scrapper.gd` |
| Crafting station | Spawn crafted item in world | `spawn_item` | `equipment/crafting_station.gd` |
| Tablet terminal | RV inventory display and recipe craft trigger | `recipes`, `_evaluate_craft_buttons` | `equipment/tablet_ui.gd`, `equipment/tablet_screen.gd` |
| RV scene assembly | Compose chassis with seat/walls/ceiling | `NewRv` scene graph | `rv/new_rv.tscn` |

## 5. Control Flow
### Main flow
1. `Chassis._ready()` configures center-of-mass, registers RV groups, and optionally pre-installs wheels.
2. Player enters driver seat via hold interaction; seat camera takes control and chassis driving state is enabled.
3. During play, chassis physics process reads input and applies engine/brake/steering dynamics.
4. Props can be recycled through scrapper into RV inventory; tablet UI reflects inventory and crafts items through station spawn.

### Error flow
1. Driver seat invoked while not mounted on RV: logs and ignores drive request.
2. Scrapper invoked off-RV: logs offline message and ejects prop.
3. Tablet craft with insufficient materials/no valid station: craft aborts with log.
4. Wheel removal fails safely when slot/chassis reference is invalid.

## 6. Data Contracts
- RV inventory dictionary stores material counts by string keys.
- Wheel slots are fixed array positions mapped by metadata (`FL/FR/RL/RR`).
- Prop recycling contract expects `Prop.scrap_yields` values as `Vector2(min,max)` quantity ranges.
- Tablet recipe contract stores `scene` output and `costs` dictionary per recipe.
- Equipment placement contract depends on valid collision/mesh dimensions for offset calculations.

## 7. Configuration Touchpoints
- Chassis tuning exports:
  - `max_engine_force`, `max_speed`, `max_braking_force`, `max_steering`, `center_of_mass_offset`.
- Wheel tuning constants:
  - radius/width, suspension and friction settings in `_create_wheel_at`.
- Driver seat camera sensitivity constant: `MOUSE_SENSITIVITY`.
- Scrapper timing constants: `crush_speed`, `crush_time`, `roller_spin_speed`.

## 8. Failure Modes and Safeguards
- Safeguards:
  - Placement confirm adds collision exceptions across ancestor chain to prevent RV self-collision launch.
  - Cancel path removes collision exceptions and restores state.
  - Driver seat setup uses `call_deferred` to avoid early RV group lookup race.
- Failure modes:
  - Hardcoded player child node paths in driver seat can break on scene refactor.
  - Wheel hitbox chassis lookup assumes fixed ancestry depth.
  - Empty `scene_file_path` on props can cause fallback to incorrect scene assumptions.

## 9. Testing and Verification
- Existing tests: none.
- Missing tests:
  - Wheel install/remove lifecycle with inventory consumption and drop behavior.
  - Seat board/exit transitions and camera ownership restoration.
  - Scrapper online/offline outcomes and yield correctness.
  - Crafting recipe gating with station-to-RV connectivity checks.
- Quick verification commands:
  - `godot --path . res://world/test_world.tscn`

## 10. Change Checklist
- [ ] API contract checked
- [ ] Backward compatibility checked
- [ ] Docs consistency checked
- [ ] Tests updated or justified

## 11. Source Files Used
- `rv/chassis.gd`
- `rv/wheel_hitbox.gd`
- `rv/chassis.tscn`
- `rv/new_rv.tscn`
- `equipment/equipment.gd`
- `equipment/driver_seat.gd`
- `equipment/rv_panel.gd`
- `equipment/scrapper.gd`
- `equipment/crafting_station.gd`
- `equipment/tablet_screen.gd`
- `equipment/tablet_ui.gd`
- `props/interactable_item.gd`
- `props/wheel.gd`
- `player/player_interact.gd`

## 12. Completeness Notes
- Covers implemented RV/equipment mechanics and contracts currently used in runtime scenes.
- Does not include legacy RV implementation details beyond noting chassis is the active path.
