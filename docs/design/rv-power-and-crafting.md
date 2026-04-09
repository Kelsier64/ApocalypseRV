# RV Power and Crafting Design

## Scope
This document describes runtime flow for RV fuel/power management and terminal-driven crafting.

Primary references:
- Chassis energy and inventory model: [rv/chassis.gd](../../rv/chassis.gd#L1)
- Generator behavior: [equipment/generator.gd](../../equipment/generator.gd#L1)
- Crafting station behavior: [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L1)
- Tablet terminal behavior: [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L1), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L1)

Related module contracts:
- RV core contracts: [docs/modules/rv-systems.md](../modules/rv-systems.md)
- Equipment contracts: [docs/modules/rv-systems-equipment.md](../modules/rv-systems-equipment.md)

## Energy Model Overview
- Chassis owns both fuel and power pools with current/max pairs.
- `step_energy_system` is the central update path for per-frame energy accounting.
- Idle behavior drains parked power; driving behavior consumes fuel and converts it into power charge.

Evidence:
- State fields: [rv/chassis.gd](../../rv/chassis.gd#L41), [rv/chassis.gd](../../rv/chassis.gd#L42), [rv/chassis.gd](../../rv/chassis.gd#L43), [rv/chassis.gd](../../rv/chassis.gd#L44)
- Energy function and idle drain: [rv/chassis.gd](../../rv/chassis.gd#L174), [rv/chassis.gd](../../rv/chassis.gd#L184)
- Drive fuel/power conversion: [rv/chassis.gd](../../rv/chassis.gd#L188), [rv/chassis.gd](../../rv/chassis.gd#L194)

## Fuel Input and Refuel Hand-Off
- Refuel action requires active player item `Gasoline Can`.
- Per can amount is controlled by `fuel_per_gas_can` and applied through `add_fuel`.
- On successful refuel, the active can is consumed and replaced with `Gasoline Can (Empty)`.

Evidence:
- Active-item gate and amount: [rv/chassis.gd](../../rv/chassis.gd#L92), [rv/chassis.gd](../../rv/chassis.gd#L50), [rv/chassis.gd](../../rv/chassis.gd#L100)
- Inventory hand-off: [rv/chassis.gd](../../rv/chassis.gd#L105), [rv/chassis.gd](../../rv/chassis.gd#L107)
- User feedback states: [rv/chassis.gd](../../rv/chassis.gd#L93), [rv/chassis.gd](../../rv/chassis.gd#L97), [rv/chassis.gd](../../rv/chassis.gd#L108)

## Generator Contribution Loop
- Chassis calls `_run_generators(delta)` inside `step_energy_system` before drive/idle branch logic.
- Generator candidates are discovered from group `rv_power_generators`.
- Only generators whose `get_connected_rv()` equals the chassis contribute power.
- Generator output is fuel-limited and proportional: generated power is capped by available fuel for the frame and remaining power capacity.

Evidence:
- Chassis-side call order and loop: [rv/chassis.gd](../../rv/chassis.gd#L178), [rv/chassis.gd](../../rv/chassis.gd#L211), [rv/chassis.gd](../../rv/chassis.gd#L218)
- RV matching filter: [rv/chassis.gd](../../rv/chassis.gd#L223)
- Generator group and API: [equipment/generator.gd](../../equipment/generator.gd#L8), [equipment/generator.gd](../../equipment/generator.gd#L10)
- Generator limiter math: [equipment/generator.gd](../../equipment/generator.gd#L24), [equipment/generator.gd](../../equipment/generator.gd#L33), [equipment/generator.gd](../../equipment/generator.gd#L34), [equipment/generator.gd](../../equipment/generator.gd#L38), [equipment/generator.gd](../../equipment/generator.gd#L39)

## Crafting Terminal Flow

### Recipe source
- Recipe data currently contains one output (`Gasoline Can`) targeting `res://props/gas_can.tscn`.
- Material costs for this recipe are `Unrefined Fuel: 5` and `Metal Parts: 2`.

Evidence:
- Recipe table: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L9), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L10), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L12), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L13)

### Open and power gate
- Tablet screen requires RV connection and usable power before opening UI.
- It charges `power_cost_per_open` via `consume_rv_power`.

Evidence:
- Open gating: [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L22), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L24), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L27)
- Open-cost export: [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L4)

### Craft dispatch
- Craft button availability depends on RV connection, usable power, and `connected_rv.has_materials(costs)`.
- On craft request, UI selects a crafting station in group `crafting_stations` connected to the same RV.
- If material deduction succeeds, the chosen station executes `spawn_item(scene_path)`.

Evidence:
- Button evaluation gates: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L116), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L121), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L124)
- Station lookup and RV match: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L138), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L145)
- Material-deduct and spawn dispatch: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L153), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L154)

### Station-side spawn
- Crafting station checks RV connection and usable power, then consumes `power_cost_per_spawn`.
- Spawned output is inserted into `get_tree().current_scene` and positioned at `SpawnMarker` when present.

Evidence:
- RV/power gates and draw: [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L14), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L16), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L25)
- Spawn destination and transform source: [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L33), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L37)
- Power-per-spawn config: [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L5)

## HUD/Terminal Feedback
- Tablet UI renders fuel and power directly from `connected_rv` values.
- It also lists RV inventory through `get_all_items()` and has explicit offline text for missing RV connection.
- Chassis emits inventory/fuel/power signals that tablet UI subscribes to on open.

Evidence:
- Fuel/power text: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L163), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L164)
- Inventory and offline message: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L169), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L160)
- Signal subscribe paths: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L109), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L111), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L113)
- Signal definitions: [rv/chassis.gd](../../rv/chassis.gd#L31), [rv/chassis.gd](../../rv/chassis.gd#L32), [rv/chassis.gd](../../rv/chassis.gd#L33)

## Test World Placement Context
- Test world includes root-level instances of generator, tablet screen, scrapper, crafting station, driver seat, and `NewRv`.
- Because `Equipment.get_connected_rv()` resolves via parent ancestry, these root-level placements imply offline behavior unless equipment is reparented under an RV ancestor at runtime.

Evidence:
- Root-level instances: [world/test_world.tscn](../../world/test_world.tscn#L52), [world/test_world.tscn](../../world/test_world.tscn#L58), [world/test_world.tscn](../../world/test_world.tscn#L61), [world/test_world.tscn](../../world/test_world.tscn#L64), [world/test_world.tscn](../../world/test_world.tscn#L76), [world/test_world.tscn](../../world/test_world.tscn#L82)
- RV ancestry contract: [equipment/equipment.gd](../../equipment/equipment.gd#L64), [equipment/equipment.gd](../../equipment/equipment.gd#L68)

## Assumptions and Unknowns
- No explicit battery cutoff, depletion fail-safe mode, or generator prioritization policy is defined beyond boolean success/failure of consume/add APIs.
  Evidence: [rv/chassis.gd](../../rv/chassis.gd#L141), [rv/chassis.gd](../../rv/chassis.gd#L156), [equipment/generator.gd](../../equipment/generator.gd#L39)
- Crafting queueing, multi-user arbitration, and persistence are not present in this evidence set; current flow appears immediate and single-action.
  Evidence: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L126), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L11)