# Module: RV Energy and Equipment

## 1. Responsibility
This module defines RV driving/resource behavior and equipment integration. It governs fuel consumption, power generation/consumption, wheel installation, and equipment placement coupling to the RV.

## 2. Boundaries and Dependencies
- `Chassis` is the central authority for fuel, power, and wheel slot state.
- Equipment modules use RV contracts via duck typing and group membership (`rv`).
- Generator nodes contribute power through group lookup (`rv_power_generators`).
- Refuel flow depends on player-held item naming (`Gasoline Can`).

## 3. Entry Points and Public Surface
Primary `Chassis` API:
- `consume_fuel(amount) -> bool`
- `add_fuel(amount) -> float`
- `consume_power(amount) -> bool`
- `add_power(amount) -> float`
- `has_usable_power(required := 0.01) -> bool`
- `step_energy_system(drive_input, braking_input, steering_input, delta) -> bool`
- `refuel_from_player(player) -> void`
- `install_wheel() -> bool`
- `remove_wheel(slot_index) -> void`

Signals:
- `inventory_changed(item_name, new_amount)`
- `fuel_changed(current, max_value)`
- `power_changed(current, max_value)`

Equipment base API:
- `get_connected_rv() -> Node3D`
- `consume_rv_power(amount) -> bool`
- `start_placement(player)`
- `confirm_placement(new_global_transform, new_parent)`
- `cancel_placement()`

## 4. Internal Structure
| Part | Role | Key Symbols | File |
|---|---|---|---|
| RV vehicle and resources | Physics control + fuel/power/inventory/wheels | `step_energy_system`, `_run_generators`, `WHEEL_SLOTS` | `rv/chassis.gd` |
| Fuel interaction point | Forwards interaction to RV refuel API | `interact(player)` | `rv/fuel_filler.gd` |
| Wheel removal interaction | Removes wheel and spawns wheel prop | `interact_hold`, `remove_wheel` | `rv/wheel_hitbox.gd` |
| Equipment base | Placement flow and RV lookup | `get_connected_rv`, `consume_rv_power` | `equipment/equipment.gd` |
| Generator | Converts fuel to power with clamping | `generate_power(rv, delta)` | `equipment/generator.gd` |
| Scrapper | Consumes power while processing props into materials | `_process`, `_finish_recycle` | `equipment/scrapper.gd` |
| Crafting station | Spawns items with RV power cost | `spawn_item(scene_path)` | `equipment/crafting_station.gd` |

## 5. Control Flow
### Main flow
1. `Chassis._ready()` clamps initial resource values and emits resource signals.
2. `Chassis._physics_process(delta)` reads input and computes drive intent.
3. `step_energy_system(drive_input, braking_input, steering_input, delta)` runs generators, applies idle drain or drive fuel burn/charge.
4. For each generator in `rv_power_generators`, `generate_power` adds capped power and consumes proportional fuel.
5. Equipment modules request power using `consume_rv_power` before executing operations.

### Error flow
1. If no fuel for requested drive force, drive force is suppressed.
2. If equipment cannot locate connected RV or RV lacks `consume_power`, power request fails.
3. Refuel exits early when player has wrong item name or tank already full.
4. Wheel removal exits safely for invalid slot indices.

## 6. Data Contracts
- Wheel slot contract in `WHEEL_SLOTS` includes `name`, `position`, `steering`, `traction`.
- RV inventory dictionary starts with `Metal Parts`, `Unrefined Fuel`, `Unknown Material`.
- Refuel item naming contract:
  - input: `Gasoline Can`
  - returned item: `Gasoline Can (Empty)` scene `res://props/gas_can_empty.tscn`.
- Generator constants:
  - default fuel consumption `0.6` per second.
  - default power generation `1.8` per second.

## 7. Configuration Touchpoints
- Chassis exported tuning fields: engine/brake/steer limits, burn/charge rates, gas can fuel amount.
- Generator exported rates for fuel/power conversion.
- Equipment bottom-face placement orientation and ghost material.

## 8. Failure Modes and Safeguards
- Fuel/power mutation methods clamp and emit signals only on meaningful changes.
- Methods return booleans/floats to indicate effective resource operations.
- Generator guards against invalid RV contract and non-positive deltas.
- Placement mode adds collision exceptions with parent chain to prevent physics explosions.

## 9. Testing and Verification
Existing tests:
- `tests/test_energy_system.gd` verifies:
  - Chassis resource API availability.
  - Fuel/power consume/add behaviors.
  - Drive and idle energy steps.
  - Generator behavior and max power cap handling.
  - Equipment power consumption forwarding.
  - Refuel full-can and empty-can behavior.

Missing tests:
- Scrapper end-to-end recycle flow and item yields.
- Crafting station spawn constraints and power accounting.
- Wheel install/remove interaction in live scene.
- Chassis integration with real VehicleBody3D physics over long sessions.

Quick verification commands:
- `godot --headless -s tests/test_energy_system.gd`
- `godot --path . res://world/test_world.tscn`

## 10. Change Checklist
- [ ] API contract checked
- [ ] Backward compatibility checked
- [ ] Docs consistency checked
- [ ] Tests updated or justified

## 11. Source Files Used
- `rv/chassis.gd`
- `rv/fuel_filler.gd`
- `rv/wheel_hitbox.gd`
- `equipment/equipment.gd`
- `equipment/generator.gd`
- `equipment/scrapper.gd`
- `equipment/crafting_station.gd`
- `equipment/driver_seat.gd`
- `tests/test_energy_system.gd`
- `tests/test_energy_system.out.txt`

## 12. Completeness Notes
This document covers resource contracts and energy flow in current scripts and tests. It does not yet specify long-term balancing targets or save/load persistence behavior.