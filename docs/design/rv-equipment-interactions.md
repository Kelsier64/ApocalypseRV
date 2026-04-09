# RV Equipment Interactions Design

## Scope
This document captures interaction behavior for RV equipment terminals and auxiliary RV interaction nodes in this partition.

Primary references:
- Base equipment placement/damage model: [equipment/equipment.gd](../../equipment/equipment.gd#L1)
- Driver seat, scrapper, crafting station, tablet scripts: [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L1), [equipment/scrapper.gd](../../equipment/scrapper.gd#L1), [equipment/crafting_station.gd](../../equipment/crafting_station.gd#L1), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L1), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L1)
- RV helper interaction nodes: [rv/fuel_filler.gd](../../rv/fuel_filler.gd#L1), [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L1)

Related module contracts:
- RV core contracts: [docs/modules/rv-systems.md](../modules/rv-systems.md)
- Equipment contracts: [docs/modules/rv-systems-equipment.md](../modules/rv-systems-equipment.md)

## Placement Lifecycle Interaction
- Equipment enters placement mode through `start_placement(player)`.
- Placement mode freezes physics as kinematic, disables collisions, applies ghost material, and asks player to enter placement control mode.
- Confirming placement reapplies static freeze, configures collision exceptions against ancestor collision objects, and restores original materials.
- Canceling placement restores original parent/local transform and removes temporary collision exceptions.

Evidence:
- Placement entry operations: [equipment/equipment.gd](../../equipment/equipment.gd#L84), [equipment/equipment.gd](../../equipment/equipment.gd#L93), [equipment/equipment.gd](../../equipment/equipment.gd#L95), [equipment/equipment.gd](../../equipment/equipment.gd#L101)
- Confirm operations: [equipment/equipment.gd](../../equipment/equipment.gd#L119), [equipment/equipment.gd](../../equipment/equipment.gd#L132), [equipment/equipment.gd](../../equipment/equipment.gd#L140), [equipment/equipment.gd](../../equipment/equipment.gd#L143)
- Cancel operations: [equipment/equipment.gd](../../equipment/equipment.gd#L149), [equipment/equipment.gd](../../equipment/equipment.gd#L163), [equipment/equipment.gd](../../equipment/equipment.gd#L167)

## Fuel Filler Interaction Flow
- Fuel filler provides `interact(player)` and resolves chassis by walking parent chain until it finds a node in group `chassis` with method `refuel_from_player`.
- Once found, it delegates all refuel logic to chassis.

Evidence:
- Interact method and delegation: [rv/fuel_filler.gd](../../rv/fuel_filler.gd#L3), [rv/fuel_filler.gd](../../rv/fuel_filler.gd#L7), [rv/fuel_filler.gd](../../rv/fuel_filler.gd#L8)
- Parent traversal + chassis gate: [rv/fuel_filler.gd](../../rv/fuel_filler.gd#L10), [rv/fuel_filler.gd](../../rv/fuel_filler.gd#L13)

## Wheel Removal Interaction Flow
- Wheel hitbox exposes `interact_hold(player)` and resolves chassis via parent chain (`WheelHitbox -> Wheel -> Chassis`).
- Removal calls `chassis.remove_wheel(slot_index)` and spawns a wheel prop at outward offset.
- Spawned wheel receives outward/upward initial velocity if rigid body.

Evidence:
- Hold interaction and chassis resolution: [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L11), [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L33)
- Slot-based removal: [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L7), [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L22)
- Spawn position and impulse: [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L18), [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L21), [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L28), [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L31)

## Driver Seat Interaction Flow
- Driver seat uses hold interaction to claim a single `current_driver`.
- Entering seat switches control context to seat camera and marks chassis driving active.
- Seat camera receives clamped mouse look while occupied.
- Pressing `E` exits seat, restores player body/camera, and clears driving state.

Evidence:
- Hold gate and driver assignment: [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L29), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L30), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L38)
- Enter and drive-enable path: [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L39), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L42), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L45)
- Camera look and clamp: [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L47), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L52), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L54), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L55)
- Exit trigger and restore path: [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L57), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L61), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L68), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L72), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L76)

## Tablet Interaction Flow
- Tablet screen pre-instantiates tablet UI and hides it.
- On powered hold interaction, tablet enters UI mode, calls `on_open`, shows UI, and wires `close_requested` signal to cleanup callback.
- Closing returns player to normal mode through `exit_ui_mode`.

Evidence:
- UI pre-instantiation: [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L10), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L12), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L13)
- Interaction gates and open path: [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L17), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L24), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L27), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L34), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L37), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L39)
- Close wiring and callback: [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L42), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L44), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L47), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L49), [equipment/tablet_screen.gd](../../equipment/tablet_screen.gd#L54)

## Scrapper Interaction Flow
- Hopper body-enter event starts flow for `Prop` only.
- On accept, prop is frozen and moved downward over time while rollers spin and RV power is consumed.
- Completion yields materials to RV inventory, then removes prop.
- If offline or unpowered, scrapper rejects and bounces prop upward.

Evidence:
- Hopper trigger and prop filter: [equipment/scrapper.gd](../../equipment/scrapper.gd#L18), [equipment/scrapper.gd](../../equipment/scrapper.gd#L56), [equipment/scrapper.gd](../../equipment/scrapper.gd#L61)
- Runtime processing and power gate: [equipment/scrapper.gd](../../equipment/scrapper.gd#L23), [equipment/scrapper.gd](../../equipment/scrapper.gd#L28), [equipment/scrapper.gd](../../equipment/scrapper.gd#L33), [equipment/scrapper.gd](../../equipment/scrapper.gd#L46)
- Yield path and fallback: [equipment/scrapper.gd](../../equipment/scrapper.gd#L113), [equipment/scrapper.gd](../../equipment/scrapper.gd#L118)
- Rejection path: [equipment/scrapper.gd](../../equipment/scrapper.gd#L67), [equipment/scrapper.gd](../../equipment/scrapper.gd#L69), [equipment/scrapper.gd](../../equipment/scrapper.gd#L72), [equipment/scrapper.gd](../../equipment/scrapper.gd#L73)

## Terminal UI Craft Interaction Flow
- `tablet_ui.gd` configures craft rows on first open and binds each button to `_craft_item(recipe_name)`.
- Crafting checks RV power and materials, locates matching connected crafting station, deducts materials, then asks station to spawn output.
- Display refreshes on inventory/fuel/power signals and shows explicit offline text when disconnected.

Evidence:
- UI setup and button binding: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L43), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L49), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L77)
- Craft execution path: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L126), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L128), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L134), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L145), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L153), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L154)
- Display and signal updates: [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L86), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L90), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L93), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L160), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L163), [equipment/tablet_ui.gd](../../equipment/tablet_ui.gd#L164)

## Runtime Placement Context in TestWorld
- `world/test_world.tscn` instantiates generator, tablet, scrapper, crafting station, and driver seat as root children, and separately instantiates `NewRv`.
- Interaction scripts that rely on RV parent traversal therefore require runtime reparenting/placement onto RV for connected behavior.

Evidence:
- Scene resources and root instances: [world/test_world.tscn](../../world/test_world.tscn#L3), [world/test_world.tscn](../../world/test_world.tscn#L5), [world/test_world.tscn](../../world/test_world.tscn#L7), [world/test_world.tscn](../../world/test_world.tscn#L8), [world/test_world.tscn](../../world/test_world.tscn#L12), [world/test_world.tscn](../../world/test_world.tscn#L52), [world/test_world.tscn](../../world/test_world.tscn#L58), [world/test_world.tscn](../../world/test_world.tscn#L61), [world/test_world.tscn](../../world/test_world.tscn#L64), [world/test_world.tscn](../../world/test_world.tscn#L76), [world/test_world.tscn](../../world/test_world.tscn#L82)
- RV traversal dependency: [equipment/equipment.gd](../../equipment/equipment.gd#L64), [equipment/equipment.gd](../../equipment/equipment.gd#L68)

## Assumptions and Unknowns
- Input hold durations and key bindings are implemented outside this evidence set; this document captures only equipment-side interaction methods (`interact`, `interact_hold`) and observed key checks inside driver seat.
  Evidence: [rv/fuel_filler.gd](../../rv/fuel_filler.gd#L3), [rv/wheel_hitbox.gd](../../rv/wheel_hitbox.gd#L11), [equipment/driver_seat.gd](../../equipment/driver_seat.gd#L57)
- `tablet_screen.tscn` confirms the tablet scene is a `RigidBody3D` with script `tablet_screen.gd`, but broader UI layout and input focus policy beyond these scripts is out of scope.
  Evidence: [equipment/tablet_screen.tscn](../../equipment/tablet_screen.tscn#L3), [equipment/tablet_screen.tscn](../../equipment/tablet_screen.tscn#L14), [equipment/tablet_screen.tscn](../../equipment/tablet_screen.tscn#L17)