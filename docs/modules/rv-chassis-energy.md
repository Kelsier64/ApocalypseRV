# RV Chassis Energy Module

## Responsibility
This module owns RV driving-state energy arbitration, chassis durability under monster attacks, and the direct coupling between chassis motion intent and resource consumption/charging. It also exposes the refuel and damage entrypoints consumed by interaction and combat nodes. [rv/chassis.gd:114] [rv/chassis.gd:151] [rv/chassis.gd:65] [rv/chassis.gd:75]

## Boundaries
- In scope:
  - Chassis fuel/power state, clamps, and change signals. [rv/chassis.gd:32] [rv/chassis.gd:33] [rv/chassis.gd:174] [rv/chassis.gd:181]
  - Chassis durability state and monster damage acceptance through `take_damage`. [rv/chassis.gd:53] [rv/chassis.gd:54] [rv/chassis.gd:75]
  - Per-frame driving control integration and engine/brake application. [rv/chassis.gd:205] [rv/chassis.gd:249] [rv/chassis.gd:260]
  - Generator polling/invocation for connected RV generators. [rv/chassis.gd:188] [rv/chassis.gd:195] [rv/chassis.gd:203]
  - Player-canister refuel acceptance and item exchange. [rv/chassis.gd:65] [rv/chassis.gd:69] [rv/chassis.gd:84]
- Out of scope:
  - Generator conversion math internals (owned by equipment generator script). [equipment/generator.gd:10]
  - Driver camera and occupancy UX details (owned by driver seat script). [equipment/driver_seat.gd:47] [equipment/driver_seat.gd:61]
  - Fuel-filler ancestor lookup interaction behavior (owned by fuel filler script). [rv/fuel_filler.gd:10]
  - Non-partition systems like building generation, enemy AI, and POI spawning.

## Entry points
- Chassis.set_driving_state(state) [rv/chassis.gd:115]
- Chassis.step_energy_system(drive_input, braking_input, steering_input, delta) [rv/chassis.gd:151]
- Chassis.refuel_from_player(player) [rv/chassis.gd:65]
- Chassis.take_damage(amount) [rv/chassis.gd:75]
- Chassis._physics_process(delta) [rv/chassis.gd:205]
- FuelFiller.interact(player) forwarding to chassis refuel [rv/fuel_filler.gd:3] [rv/fuel_filler.gd:8]
- DriverSeat.interact_hold(player) and exit_seat() toggling driving mode [equipment/driver_seat.gd:29] [equipment/driver_seat.gd:76]

## Internal structure table
| Component | Type | Key data | Key methods | Notes |
| --- | --- | --- | --- | --- |
| Chassis | VehicleBody3D | current_fuel, max_fuel, current_power, max_power, burn/charge rates, max_chassis_health, current_chassis_health, chassis_destroyed | step_energy_system, consume_fuel, add_power, refuel_from_player, take_damage, _physics_process | Central authority for this partition. [rv/chassis.gd:1] [rv/chassis.gd:41] [rv/chassis.gd:151] [rv/chassis.gd:53] [rv/chassis.gd:75] |
| FuelFiller | StaticBody3D | none persistent in script | interact, _get_chassis | Interaction proxy to chassis refuel API. [rv/fuel_filler.gd:1] [rv/fuel_filler.gd:3] |
| Generator | Equipment | fuel_consumption_per_second, power_generation_per_second | generate_power | Optional supplemental conversion path fuel -> power. [equipment/generator.gd:3] [equipment/generator.gd:10] |
| DriverSeat | Equipment | current_driver, seat_camera | interact_hold, _unhandled_input, exit_seat | Owns entering/exiting driving control. [equipment/driver_seat.gd:7] [equipment/driver_seat.gd:29] |

## Control flow
1. Driver seat interaction mounts player and sets chassis driving flag true. [equipment/driver_seat.gd:38] [equipment/driver_seat.gd:45]
2. Chassis physics tick reads input and computes drive intent with steering and speed factors. [rv/chassis.gd:211] [rv/chassis.gd:237] [rv/chassis.gd:247]
3. Chassis energy step executes generator pass first, then parked drain or drive burn + charge path. [rv/chassis.gd:155] [rv/chassis.gd:160] [rv/chassis.gd:165] [rv/chassis.gd:171]
4. If fuel is insufficient for requested drive intensity, energy step returns false and physics step blocks drive force. [rv/chassis.gd:167] [rv/chassis.gd:250]
5. Fuel-filler interaction delegates to chassis refuel, which validates active item and may exchange can state. [rv/fuel_filler.gd:8] [rv/chassis.gd:69] [rv/chassis.gd:84]
6. Exiting seat restores player control and sets chassis driving false. [equipment/driver_seat.gd:68] [equipment/driver_seat.gd:76]

## Data contracts
- Fuel contract:
  - current_fuel is clamped to [0, max_fuel] through _set_fuel(). [rv/chassis.gd:174]
  - consume_fuel(amount) returns false when amount exceeds available fuel. [rv/chassis.gd:121] [rv/chassis.gd:122]
  - add_fuel(amount) returns the effective added amount after clamp. [rv/chassis.gd:126] [rv/chassis.gd:131]
- Power contract:
  - current_power is clamped to [0, max_power] through _set_power(). [rv/chassis.gd:181]
  - consume_power(amount) returns false on insufficient power. [rv/chassis.gd:136] [rv/chassis.gd:137]
  - has_usable_power(required) compares against non-negative required threshold. [rv/chassis.gd:148] [rv/chassis.gd:149]
- Refuel contract:
  - Requires player.get_active_item_name() == Gasoline Can. [rv/chassis.gd:66] [rv/chassis.gd:69]
  - On success, consumes active item when method exists and adds Gasoline Can (Empty). [rv/chassis.gd:81] [rv/chassis.gd:84]
  - No-op when tank is near full. [rv/chassis.gd:73]
- Generator contract:
  - generate_power(rv, delta) requires RV consume_fuel/add_power methods and relevant RV fields. [equipment/generator.gd:15] [equipment/generator.gd:17]
  - Generated power is capped by missing power and available fuel. [equipment/generator.gd:24] [equipment/generator.gd:33] [equipment/generator.gd:34]
- Durability contract:
  - chassis is discoverable by monster AI through `monster_damageable` group membership. [rv/chassis.gd:59]
  - `take_damage(amount)` reduces `current_chassis_health` and flips `chassis_destroyed` at zero durability. [rv/chassis.gd:75] [rv/chassis.gd:87]
  - Once destroyed, drive state is forced off and engine output is cut. [rv/chassis.gd:88] [rv/chassis.gd:90]

## Config touchpoints
- Runtime scene is world/test_world.tscn, which hosts RV systems during normal play. [project.godot:16]
- Project uses Godot 4.6 feature flag and GL Compatibility renderer, relevant when assessing physics/render behavior interactions in this module. [project.godot:17] [project.godot:32]
- 3D physics engine is Jolt Physics, affecting chassis motion characteristics under VehicleBody3D. [project.godot:27] [rv/chassis.gd:1]

## Failure modes
- Driving command rejected due to insufficient fuel at requested intensity; engine force drops to zero branch. [rv/chassis.gd:167] [rv/chassis.gd:251]
- Power can reach zero while parked; parked drain path explicitly sets zero on failure. [rv/chassis.gd:161] [rv/chassis.gd:162]
- Refuel attempts fail silently for missing player methods or wrong active item string. [rv/chassis.gd:66] [rv/chassis.gd:69]
- Generator operation may silently no-op for invalid RV links, zero rates, full battery, or failed fuel consumption. [equipment/generator.gd:13] [equipment/generator.gd:25] [equipment/generator.gd:30] [equipment/generator.gd:39]
- Fuel filler may fail to find chassis if hierarchy/group assumptions are broken. [rv/fuel_filler.gd:11] [rv/fuel_filler.gd:13] [rv/fuel_filler.gd:16]
- Chassis can be rendered undrivable after repeated monster attacks once durability reaches zero. [rv/chassis.gd:87] [rv/chassis.gd:90]

## Testing
- Automated SceneTree tests assert chassis API surface for fuel/power/step/refuel methods. [tests/test_energy_system.gd:32] [tests/test_energy_system.gd:40]
- Behavior tests cover fuel/power consume logic and drive/idle energy transitions. [tests/test_energy_system.gd:51] [tests/test_energy_system.gd:70]
- Generator tests cover consumption/charge and near-cap upper bound behavior. [tests/test_energy_system.gd:96] [tests/test_energy_system.gd:103]
- Refuel tests cover full-can success path and empty-can rejection path. [tests/test_energy_system.gd:134] [tests/test_energy_system.gd:148] [tests/test_energy_system.gd:151]
- Durability tests cover chassis damage API surface and health reduction behavior under monster-style damage. [tests/test_energy_system.gd:158] [tests/test_energy_system.gd:169]
- Monster targeting filter tests cover acceptance of standalone equipment targets without RV-parent constraints. [tests/test_energy_system.gd:172] [tests/test_energy_system.gd:180]

## Change checklist
- Confirm any change to exported burn/charge constants keeps test expectations valid. [rv/chassis.gd:46] [tests/test_energy_system.gd:64]
- If adding new driving states, keep seat toggle integration aligned with set_driving_state entrypoint. [equipment/driver_seat.gd:45] [rv/chassis.gd:115]
- If changing generator group name or connection lookup, update both generator registration and chassis polling. [equipment/generator.gd:8] [rv/chassis.gd:195]
- If changing refuel item names, update chassis string checks and test fixtures together. [rv/chassis.gd:69] [tests/test_energy_system.gd:6] [tests/test_energy_system.gd:147]
- Re-run headless energy tests after modifications to this partition. [tests/test_energy_system.gd:165]

## Source Files Used
- rv/chassis.gd
- rv/fuel_filler.gd
- equipment/generator.gd
- equipment/driver_seat.gd
- tests/test_energy_system.gd
- project.godot
- GDD.md

## Completeness notes
- Assumption: this module intentionally allows arrow-key fallback for remote control/testing even outside seat-driven mode, because behavior is explicitly implemented but not described in design docs. [rv/chassis.gd:218] [rv/chassis.gd:226]
- Unknown: exact desired balancing targets for fuel_per_gas_can, generator rates, and parked drain are not defined in GDD or project settings evidence set. [rv/chassis.gd:50] [equipment/generator.gd:3] [equipment/generator.gd:4] [GDD.md:35]
- Unknown: no explicit persistence/save contract for fuel/power state appears in this partition.
