# RV Energy and Driving Design

## Why
The RV is the shared survival core and must sustain long-running play loops where driving, powering onboard equipment, and fuel logistics continuously interact. This aligns with the GDD statement that the RV is the only shelter and a shared life system with explicit energy management of fuel and electrical power. [GDD.md:20] [GDD.md:27]

## Problem
The gameplay loop needs deterministic runtime rules for:
- when driving is allowed or blocked,
- how fuel and power are consumed or generated,
- how player interaction performs refueling,
- and how this behavior is validated in automated tests.

Current behavior is spread across chassis driving code, fuel-filler interaction, generator equipment behavior, and energy tests. [rv/chassis.gd:151] [rv/fuel_filler.gd:3] [equipment/generator.gd:10] [tests/test_energy_system.gd:24]

## Goals
- Keep fuel and power as separate resources with explicit max and current values, and signal-based UI/event hooks. [rv/chassis.gd:32] [rv/chassis.gd:33] [rv/chassis.gd:41] [rv/chassis.gd:44]
- Charge power while driving, drain power while parked, and consume fuel for both propulsion and generator operation. [rv/chassis.gd:165] [rv/chassis.gd:171] [rv/chassis.gd:161] [equipment/generator.gd:39]
- Block drive force when required fuel is unavailable, while still allowing non-driving chassis stabilization behavior. [rv/chassis.gd:167] [rv/chassis.gd:250] [rv/chassis.gd:228]
- Require a full gas can item for refuel and return an empty can after successful refuel. [rv/chassis.gd:69] [rv/chassis.gd:84] [tests/test_energy_system.gd:136] [tests/test_energy_system.gd:140]
- Expose a chassis durability surface so monster attacks can damage the base vehicle body. [rv/chassis.gd:75] [rv/chassis.gd:87]

## Tradeoffs
- Generator dispatch uses group discovery each step (rv_power_generators), which is flexible for multiple installed generators but couples runtime to scene-tree group integrity. [rv/chassis.gd:195] [equipment/generator.gd:8]
- Energy simulation is frame-step based with delta scaling, which is simple and deterministic per frame but sensitive to large delta spikes if not externally bounded. [rv/chassis.gd:151] [rv/chassis.gd:165] [equipment/generator.gd:28]
- Driving input includes arrow-key fallback even when player-driving mode is off, improving testing/control convenience but introducing non-diegetic control paths for production unless gated later. [rv/chassis.gd:218] [rv/chassis.gd:226]

## Workflow
1. Driver enters the driver seat via hold interaction; seat marks itself occupied and sets chassis driving state true. [equipment/driver_seat.gd:29] [equipment/driver_seat.gd:45]
2. Chassis physics tick reads driving/brake/steer inputs (WASD, Space, and arrow-key fallback) and computes steering and drive intent. [rv/chassis.gd:211] [rv/chassis.gd:216] [rv/chassis.gd:219] [rv/chassis.gd:247]
3. Energy step runs before applying engine force:
   - calls generator pass,
   - drains parked power when not driving,
   - or consumes fuel and charges power when driving. [rv/chassis.gd:155] [rv/chassis.gd:160] [rv/chassis.gd:165] [rv/chassis.gd:171]
4. If driving fuel is insufficient, the physics step suppresses engine force and applies braking fallback. [rv/chassis.gd:167] [rv/chassis.gd:251] [rv/chassis.gd:252]
5. On exit-seat input, seat restores player control and toggles chassis driving state false. [equipment/driver_seat.gd:57] [equipment/driver_seat.gd:61] [equipment/driver_seat.gd:76]
6. Refuel flow: interacting with fuel filler finds ancestor chassis and delegates to chassis refuel logic, which validates active item and exchanges full can for empty can. [rv/fuel_filler.gd:3] [rv/fuel_filler.gd:13] [rv/chassis.gd:69] [rv/chassis.gd:84]

## Interfaces
- Chassis public resource API:
  - consume_fuel(amount) -> bool [rv/chassis.gd:118]
  - add_fuel(amount) -> float [rv/chassis.gd:126]
  - consume_power(amount) -> bool [rv/chassis.gd:133]
  - add_power(amount) -> float [rv/chassis.gd:141]
  - has_usable_power(required) -> bool [rv/chassis.gd:148]
  - step_energy_system(drive_input, braking_input, steering_input, delta) -> bool [rv/chassis.gd:151]
  - refuel_from_player(player) -> void [rv/chassis.gd:65]
  - take_damage(amount) -> void [rv/chassis.gd:75]
- Driver seat control interface:
  - interact_hold(player) to start driving [equipment/driver_seat.gd:29]
  - exit_seat() to stop driving [equipment/driver_seat.gd:61]
- Fuel filler interaction interface:
  - interact(player) delegates to ancestor chassis [rv/fuel_filler.gd:3] [rv/fuel_filler.gd:8]
- Generator interface:
  - generate_power(rv, delta) consumes fuel and adds power on connected RV [equipment/generator.gd:10] [equipment/generator.gd:39] [equipment/generator.gd:40]

## Edge cases
- Refuel is ignored when player node is invalid or lacks expected item method. [rv/chassis.gd:66]
- Refuel is denied for non-full gas can item names and when tank is already near full. [rv/chassis.gd:69] [rv/chassis.gd:73]
- Parked drain clamps to zero when insufficient power remains. [rv/chassis.gd:161] [rv/chassis.gd:162]
- Generator silently skips invalid RV references, missing methods, zero/negative rates, or already-full power state. [equipment/generator.gd:13] [equipment/generator.gd:15] [equipment/generator.gd:25] [equipment/generator.gd:30]
- Chassis generator pass ignores generators not connected to this chassis instance. [rv/chassis.gd:200]
- Chassis can enter destroyed state after repeated monster damage, forcing driving state off. [rv/chassis.gd:87] [rv/chassis.gd:88]

## Validation
- API presence checks for chassis resource and refuel functions are covered in automated tests. [tests/test_energy_system.gd:34] [tests/test_energy_system.gd:40]
- Resource behavior tests validate consume/add semantics, driving fuel burn, driving power charge, and parked drain. [tests/test_energy_system.gd:51] [tests/test_energy_system.gd:64] [tests/test_energy_system.gd:65] [tests/test_energy_system.gd:70]
- Generator behavior tests validate power increase, fuel consumption, and near-full non-overfill behavior. [tests/test_energy_system.gd:97] [tests/test_energy_system.gd:98] [tests/test_energy_system.gd:103]
- Gas can tests validate full-can success and empty-can no-op behavior. [tests/test_energy_system.gd:136] [tests/test_energy_system.gd:150] [tests/test_energy_system.gd:151]
- Durability tests validate chassis damage API and monster target-filter behavior for standalone equipment. [tests/test_energy_system.gd:158] [tests/test_energy_system.gd:172]

## Related modules
- Chassis runtime and energy authority: rv/chassis.gd [rv/chassis.gd:1]
- Driver interaction bridge to driving state: equipment/driver_seat.gd [equipment/driver_seat.gd:29]
- Refuel interaction proxy: rv/fuel_filler.gd [rv/fuel_filler.gd:3]
- Auxiliary fuel-to-power conversion: equipment/generator.gd [equipment/generator.gd:10]
- Acceptance behavior coverage: tests/test_energy_system.gd [tests/test_energy_system.gd:24]
- Engine/runtime context for this partition: project.godot (Godot 4.6, Jolt Physics, GL Compatibility) [project.godot:17] [project.godot:27] [project.godot:32]

## Source Files Used
- rv/chassis.gd
- rv/fuel_filler.gd
- equipment/generator.gd
- equipment/driver_seat.gd
- tests/test_energy_system.gd
- project.godot
- GDD.md

## Completeness notes
- Assumption: regenerative charge while driving (power_charge_per_second_driving) is intended to represent alternator-like behavior; the implementation exists but design intent wording is inferred from variable naming and test expectations. [rv/chassis.gd:48] [tests/test_energy_system.gd:65]
- Unknown: no explicit balancing targets are defined for fuel economy, power economy, or intended time-to-empty/time-to-full values beyond exported defaults. [rv/chassis.gd:46] [rv/chassis.gd:50] [equipment/generator.gd:3] [equipment/generator.gd:4]
- Unknown: no explicit gear/handbrake state machine is implemented in this partition despite GDD wording mentioning those concepts. [GDD.md:21] [rv/chassis.gd:249]
