# RV Systems Equipment Module Contract

## Module Purpose
This module defines contracts for RV-adjacent equipment nodes that consume/provide RV resources or expose interaction terminals.

Implementation references:
- Base equipment contract: [equipment/equipment.gd](../../equipment/equipment.gd#L1)
- Generator: [equipment/generator.gd](../../equipment/generator.gd#L1)
- Driver seat: [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L1)
- Scrapper: [equipment/scrapper.gd](../../equipment/scrapper.gd#L1)
- Crafting station: [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L1)
- Tablet screen and UI: [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L1), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L1)
- RV panel helper: [equipment/rv_panel.gd](../../equipment/rv_panel.gd#L1)

Detailed behavior walk-throughs:
- Power + crafting behavior: [docs/design/rv-power-and-crafting.md](../design/rv-power-and-crafting.md)
- Interaction and terminal flow: [docs/design/rv-equipment-interactions.md](../design/rv-equipment-interactions.md)

## Base Equipment Contract (`Equipment`)
- `Equipment` extends `RigidBody3D` and exports `equipment_name`, placement orientation (`bottom_face`), and durability controls.
- RV connectivity is duck-typed by parent traversal requiring `add_item`, `deduct_materials`, and group `rv`.
- Power draw helper contract is `consume_rv_power(amount)`.
- Placement lifecycle is `start_placement`, `confirm_placement`, `cancel_placement`; on confirm/cancel it freezes as static body and configures collision exceptions with ancestors.
- Destroyable equipment adds itself to `monster_damageable` and calls `_on_before_destroy` before queue_free.

Evidence:
- Class and exports: [equipment/equipment.gd](../../equipment/equipment.gd#L2), [equipment/equipment.gd](../../equipment/equipment.gd#L6), [equipment/equipment.gd](../../equipment/equipment.gd#L11), [equipment/equipment.gd](../../equipment/equipment.gd#L12), [equipment/equipment.gd](../../equipment/equipment.gd#L13)
- RV detection contract: [equipment/equipment.gd](../../equipment/equipment.gd#L64), [equipment/equipment.gd](../../equipment/equipment.gd#L68)
- Power helper: [equipment/equipment.gd](../../equipment/equipment.gd#L73), [equipment/equipment.gd](../../equipment/equipment.gd#L79)
- Placement API: [equipment/equipment.gd](../../equipment/equipment.gd#L84), [equipment/equipment.gd](../../equipment/equipment.gd#L119), [equipment/equipment.gd](../../equipment/equipment.gd#L149)
- Placement collision/freeze policy: [equipment/equipment.gd](../../equipment/equipment.gd#L132), [equipment/equipment.gd](../../equipment/equipment.gd#L140), [equipment/equipment.gd](../../equipment/equipment.gd#L143), [equipment/equipment.gd](../../equipment/equipment.gd#L167), [equipment/equipment.gd](../../equipment/equipment.gd#L168)
- Destruction hook path: [equipment/equipment.gd](../../equipment/equipment.gd#L61), [equipment/equipment.gd](../../equipment/equipment.gd#L173), [equipment/equipment.gd](../../equipment/equipment.gd#L190)

## Generator Contract
- Generator inherits `Equipment` and joins group `rv_power_generators`.
- `generate_power(rv, delta)` is the chassis-callable contract.
- Generation requires RV methods `consume_fuel` and `add_power`, computes fuel-limited output, and applies proportional fuel burn.

Evidence:
- Group registration and API: [equipment/generator.gd](../../equipment/generator.gd#L8), [equipment/generator.gd](../../equipment/generator.gd#L10)
- Required RV methods: [equipment/generator.gd](../../equipment/generator.gd#L15)
- Rate exports and formula: [equipment/generator.gd](../../equipment/generator.gd#L3), [equipment/generator.gd](../../equipment/generator.gd#L4), [equipment/generator.gd](../../equipment/generator.gd#L33), [equipment/generator.gd](../../equipment/generator.gd#L38), [equipment/generator.gd](../../equipment/generator.gd#L39), [equipment/generator.gd](../../equipment/generator.gd#L40)

## Driver Seat Contract
- Driver seat enters drive mode on `interact_hold(player)` when mounted on an RV.
- Entering seat hides/disables player body and switches to seat camera.
- Exiting on `KEY_E` restores player collision/visibility, moves player to seat side, and disables RV driving state.
- Destroy hook guarantees occupant ejection by calling `exit_seat` if occupied.

Evidence:
- Setup and RV mount requirement: [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L15), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L29), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L33)
- Enter state changes: [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L39), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L40), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L41), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L42), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L45)
- Exit key and restoration: [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L57), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L61), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L68), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L71), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L76)
- Destroy safety: [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L80), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L82)

## Scrapper Contract
- Scrapper subscribes to `HopperArea.body_entered` and only processes `Prop` bodies.
- Accepted props are frozen and collision-disabled, then crushed over `crush_time` while consuming RV power each frame.
- Recycling outputs material yields into RV inventory or falls back to `Unknown Material`.
- If no RV connection or no usable power, it rejects input and applies upward impulse to bounce props out.

Evidence:
- Hopper wiring and prop gate: [equipment/scrapper.gd](../../equipment/scrapper.gd#L18), [equipment/scrapper.gd](../../equipment/scrapper.gd#L56), [equipment/scrapper.gd](../../equipment/scrapper.gd#L61)
- Crush controls and power draw: [equipment/scrapper.gd](../../equipment/scrapper.gd#L8), [equipment/scrapper.gd](../../equipment/scrapper.gd#L10), [equipment/scrapper.gd](../../equipment/scrapper.gd#L28)
- Prop freeze/collision off: [equipment/scrapper.gd](../../equipment/scrapper.gd#L83), [equipment/scrapper.gd](../../equipment/scrapper.gd#L85), [equipment/scrapper.gd](../../equipment/scrapper.gd#L86)
- Yield path: [equipment/scrapper.gd](../../equipment/scrapper.gd#L113), [equipment/scrapper.gd](../../equipment/scrapper.gd#L118)
- Offline rejection path: [equipment/scrapper.gd](../../equipment/scrapper.gd#L67), [equipment/scrapper.gd](../../equipment/scrapper.gd#L69), [equipment/scrapper.gd](../../equipment/scrapper.gd#L72), [equipment/scrapper.gd](../../equipment/scrapper.gd#L73)

## Crafting Station Contract
- Crafting station joins group `crafting_stations` and exposes `spawn_item(scene_path)`.
- Spawn operation requires RV connection, usable power, and successful `consume_rv_power(power_cost_per_spawn)`.
- Spawned item is added to current scene and placed at `SpawnMarker` transform when available.

Evidence:
- Group/API and power cost: [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L5), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L9), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L11)
- Connection/power gates: [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L14), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L16), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L25)
- Spawn placement: [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L4), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L33), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L37)

## Tablet Terminal Contract

### TabletScreen wrapper
- `tablet_screen.gd` pre-instantiates `res://equipment/tablet_ui.tscn` once, keeps it hidden, and reveals it on powered `interact_hold(player)`.
- Opening tablet requests `player.enter_ui_mode()`, calls `ui_instance.on_open()`, and binds close handling to `_on_ui_close(player)`.
- Close handling hides UI and requests `player.exit_ui_mode()`.

Evidence:
- UI preload and storage: [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L10), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L12), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L13)
- Open power gates: [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L22), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L24), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L27)
- UI mode and open call: [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L33), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L34), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L36), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L37)
- Close signal rebinding and close callback: [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L44), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L45), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L47), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L49), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L54)

### TabletUI content contract
- UI exposes `close_requested` and defines one recipe (`Gasoline Can`) costing `Unrefined Fuel: 5` and `Metal Parts: 2`.
- On open, it resolves RV from parent tablet screen, reconnects RV signals, and updates inventory/power/fuel display.
- Crafting requires RV connection, usable power, material check, and a crafting station connected to the same RV before `deduct_materials` + `spawn_item`.

Evidence:
- Signal and recipe config: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L3), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L9), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L12), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L13)
- Open and RV signal wiring: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L30), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L34), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L37), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L40), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L109), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L111), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L113)
- Crafting gate and dispatch: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L128), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L134), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L138), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L145), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L153), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L154)
- Inventory/fuel/power text render: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L160), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L163), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L164), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L169)

## RV Panel Contract
- RV panel follows the same deferred-on-RV setup pattern as driver seat: static freeze plus collision exceptions with ancestors when mounted.
- This script currently has no explicit interaction methods in scope.

Evidence:
- Deferred setup and collision exceptions: [equipment/rv_panel.gd](../../equipment/rv_panel.gd#L5), [equipment/rv_panel.gd](../../equipment/rv_panel.gd#L7), [equipment/rv_panel.gd](../../equipment/rv_panel.gd#L18)

## Scene Wiring Notes
- In `world/test_world.tscn`, equipment instances (Generator, TabletScreen, Scrapper, CraftingStation, DriverSeat) are added as direct children of world root.
- `NewRv` is also a direct child in the same scene.

Evidence:
- Equipment scene resources: [world/test_world.tscn](../../world/test_world.tscn#L3), [world/test_world.tscn](../../world/test_world.tscn#L5), [world/test_world.tscn](../../world/test_world.tscn#L7), [world/test_world.tscn](../../world/test_world.tscn#L8), [world/test_world.tscn](../../world/test_world.tscn#L12)
- Root-level node instances: [world/test_world.tscn](../../world/test_world.tscn#L52), [world/test_world.tscn](../../world/test_world.tscn#L58), [world/test_world.tscn](../../world/test_world.tscn#L61), [world/test_world.tscn](../../world/test_world.tscn#L64), [world/test_world.tscn](../../world/test_world.tscn#L76), [world/test_world.tscn](../../world/test_world.tscn#L82)

## Assumptions and Unknowns
- The base RV connectivity contract in `Equipment.get_connected_rv()` depends on scene hierarchy, not explicit references. Runtime behavior when equipment stays outside RV ancestry is inferred as offline from guards, but cross-scene placement intent is not defined in this partition.
  Evidence: [equipment/equipment.gd](../../equipment/equipment.gd#L64), [equipment/equipment.gd](../../equipment/equipment.gd#L68), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L22), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L14)
- Tablet UI assumes `connected_rv` exposes direct fields (`current_fuel`, `max_fuel`, `current_power`, `max_power`) and methods (`has_materials`, `deduct_materials`, `get_all_items`) without interface typing.
  Evidence: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L163), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L164), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L134), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L153), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L169)