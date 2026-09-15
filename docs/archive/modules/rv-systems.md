# RV Systems Module Contract

## Module Purpose
This module defines the RV runtime contracts for chassis driving, fuel/power state, storage inventory, and wheel management.

Implementation references:
- Chassis core: [rv/chassis.gd](../../rv/chassis.gd#L1)
- Fuel filler interaction adapter: [rv/fuel_filler.gd](../../rv/fuel_filler.gd#L1)
- Wheel removal hitbox behavior: [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L1)

Detailed behavior walk-throughs:
- Power generation and crafting flow: [docs/design/rv-power-and-crafting.md](../design/rv-power-and-crafting.md)
- Equipment interaction flow: [docs/design/rv-equipment-interactions.md](../design/rv-equipment-interactions.md)
- Equipment-side contracts: [docs/modules/rv-systems-equipment.md](rv-systems-equipment.md)

## Chassis Identity and Runtime Signals
- Chassis runtime type is `Chassis` and registers itself in `rv`, `chassis`, and `monster_damageable` groups.
- The module emits `inventory_changed`, `fuel_changed`, and `power_changed` signals for UI/terminal listeners.
- Fuel and power are clamped and signal-emitted in `_ready`.

Evidence:
- Class and groups: [rv/chassis.gd](../../rv/chassis.gd#L2), [rv/chassis.gd](../../rv/chassis.gd#L60), [rv/chassis.gd](../../rv/chassis.gd#L61), [rv/chassis.gd](../../rv/chassis.gd#L62)
- Signal contract: [rv/chassis.gd](../../rv/chassis.gd#L31), [rv/chassis.gd](../../rv/chassis.gd#L32), [rv/chassis.gd](../../rv/chassis.gd#L33)
- Clamp and initial emit: [rv/chassis.gd](../../rv/chassis.gd#L63), [rv/chassis.gd](../../rv/chassis.gd#L64), [rv/chassis.gd](../../rv/chassis.gd#L66), [rv/chassis.gd](../../rv/chassis.gd#L67)

## Fuel and Power Data Contract
- Scalar fuel/power state is represented by `current_fuel`, `max_fuel`, `current_power`, and `max_power`.
- External systems should consume/add resources through `consume_fuel`, `add_fuel`, `consume_power`, `add_power`, and `has_usable_power`.
- Refueling from player inventory is mediated by `refuel_from_player` and requires active item name `Gasoline Can`.

Evidence:
- State variables: [rv/chassis.gd](../../rv/chassis.gd#L41), [rv/chassis.gd](../../rv/chassis.gd#L42), [rv/chassis.gd](../../rv/chassis.gd#L43), [rv/chassis.gd](../../rv/chassis.gd#L44)
- Fuel/power API surface: [rv/chassis.gd](../../rv/chassis.gd#L141), [rv/chassis.gd](../../rv/chassis.gd#L149), [rv/chassis.gd](../../rv/chassis.gd#L156), [rv/chassis.gd](../../rv/chassis.gd#L164), [rv/chassis.gd](../../rv/chassis.gd#L171)
- Player refuel gate: [rv/chassis.gd](../../rv/chassis.gd#L88), [rv/chassis.gd](../../rv/chassis.gd#L92), [rv/chassis.gd](../../rv/chassis.gd#L100)

## Inventory and Crafting Materials Contract
- RV inventory keys are dictionary-backed and include `Metal Parts`, `Unrefined Fuel`, and `Unknown Material` by default.
- Contract methods for terminals are `add_item`, `has_materials`, `deduct_materials`, `get_item_count`, and `get_all_items`.
- `deduct_materials` must be preceded by `has_materials` success and emits inventory updates per item.

Evidence:
- Inventory defaults: [rv/chassis.gd](../../rv/chassis.gd#L35)
- API surface: [rv/chassis.gd](../../rv/chassis.gd#L111), [rv/chassis.gd](../../rv/chassis.gd#L118), [rv/chassis.gd](../../rv/chassis.gd#L124), [rv/chassis.gd](../../rv/chassis.gd#L131), [rv/chassis.gd](../../rv/chassis.gd#L134)
- Event emission path: [rv/chassis.gd](../../rv/chassis.gd#L115), [rv/chassis.gd](../../rv/chassis.gd#L128)

## Driving and Energy Loop Contract
- Driving enable/disable is controlled by `set_driving_state`.
- `_physics_process` reads keyboard input and routes energy accounting through `step_energy_system`.
- `step_energy_system` drains parked power when idle, consumes fuel when drive intent exists, and charges power while driving.
- Generator integration is pull-based each energy step via `_run_generators` scanning `rv_power_generators` and filtering on `get_connected_rv() == self`.

Evidence:
- Driving state API: [rv/chassis.gd](../../rv/chassis.gd#L138)
- Physics loop and idle branch: [rv/chassis.gd](../../rv/chassis.gd#L228), [rv/chassis.gd](../../rv/chassis.gd#L249)
- Energy function and coefficients: [rv/chassis.gd](../../rv/chassis.gd#L174), [rv/chassis.gd](../../rv/chassis.gd#L46), [rv/chassis.gd](../../rv/chassis.gd#L47), [rv/chassis.gd](../../rv/chassis.gd#L48), [rv/chassis.gd](../../rv/chassis.gd#L49)
- Generator bridge: [rv/chassis.gd](../../rv/chassis.gd#L211), [rv/chassis.gd](../../rv/chassis.gd#L218), [rv/chassis.gd](../../rv/chassis.gd#L221), [rv/chassis.gd](../../rv/chassis.gd#L223), [rv/chassis.gd](../../rv/chassis.gd#L226)

## Wheel Subsystem Contract
- Wheel slots are fixed in `WHEEL_SLOTS` with front steering and rear traction flags.
- Optional pre-install path creates all wheel nodes on `_ready` when `pre_install_wheels` is true.
- Public wheel API is `install_wheel`, `remove_wheel`, and `get_installed_wheel_count`.
- Created wheel nodes embed a `WheelHitbox` static body that runs `res://rv/wheel_hitbox.gd` with assigned `slot_index`.

Evidence:
- Slot declaration: [rv/chassis.gd](../../rv/chassis.gd#L13)
- Pre-install flag and call path: [rv/chassis.gd](../../rv/chassis.gd#L26), [rv/chassis.gd](../../rv/chassis.gd#L68)
- Wheel API: [rv/chassis.gd](../../rv/chassis.gd#L299), [rv/chassis.gd](../../rv/chassis.gd#L306), [rv/chassis.gd](../../rv/chassis.gd#L315)
- Hitbox attachment: [rv/chassis.gd](../../rv/chassis.gd#L364), [rv/chassis.gd](../../rv/chassis.gd#L365)

## Fuel Filler and Wheel Hitbox Integration Contracts

### Fuel filler
- `fuel_filler.gd` exposes `interact(player)` and resolves the owning chassis by walking parent nodes until a `chassis` group node exposing `refuel_from_player` is found.
- On success, it delegates refuel logic to `chassis.refuel_from_player(player)`.

Evidence:
- Fuel filler interaction path: [rv/fuel_filler.gd](../../rv/fuel_filler.gd#L3), [rv/fuel_filler.gd](../../rv/fuel_filler.gd#L10), [rv/fuel_filler.gd](../../rv/fuel_filler.gd#L13)

### Wheel hitbox
- `wheel_hitbox.gd` exposes `interact_hold(player)` and calls `chassis.remove_wheel(slot_index)`.
- After removal, it spawns a wheel prop and applies outward/upward velocity impulse.

Evidence:
- Wheel removal call path: [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L11), [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L22)
- Spawn and impulse behavior: [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L24), [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L28), [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L31)

## Durability Contract
- Chassis exposes durability through `max_chassis_health`, `current_chassis_health`, and `take_damage`.
- On zero health, driving is disabled, engine force is cleared, and braking is forced.

Evidence:
- Durability fields: [rv/chassis.gd](../../rv/chassis.gd#L53), [rv/chassis.gd](../../rv/chassis.gd#L54)
- Damage behavior: [rv/chassis.gd](../../rv/chassis.gd#L72), [rv/chassis.gd](../../rv/chassis.gd#L84)

## Assumptions and Unknowns
- `refuel_from_player` calls `player.add_item(EMPTY_GAS_CAN_ITEM_NAME, false, EMPTY_GAS_CAN_SCENE)`; player inventory API shape is outside this partition, so compatibility is assumed.
  Evidence: [rv/chassis.gd](../../rv/chassis.gd#L107)
- Wheel install interaction timing and input bindings are implemented in the player interaction script, which is outside this evidence set.
  Evidence: [rv/chassis.gd](../../rv/chassis.gd#L299), [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L11)