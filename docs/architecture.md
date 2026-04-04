# ApocalypseRV Architecture

## 1. Purpose and Scope
ApocalypseRV is a cooperative first-person survival game prototype in Godot 4.6. The current implementation focuses on three runtime pillars:
- Streaming highway world generation with POIs.
- Player interaction, inventory, and combat survival loops.
- RV-centered fuel and power economy that drives equipment usage.

In scope:
- Runtime gameplay logic under `world/`, `player/`, `rv/`, `equipment/`, `enemies/`, `props/`.
- One playable test scene at `world/test_world.tscn`.

Out of scope (in current repository state):
- Multiplayer netcode implementation details.
- Persistence/save migration strategy.
- Deployment packaging pipeline.

## 2. Goals and Non-Goals
### Goals
- Keep a playable vertical slice with clear gameplay loops.
- Allow fast iteration by composing systems with scene/script contracts.
- Maintain deterministic-enough resource rules for fuel and power.

### Non-Goals
- Full production hardening of every subsystem.
- Deep anti-cheat/security architecture.
- Comprehensive automated test coverage across all gameplay modules.

## 3. System Context
- Engine/runtime: Godot 4.6 with GL Compatibility renderer.
- Physics backend: Jolt Physics.
- Entry scene: `res://world/test_world.tscn`.
- Main external dependency is Godot runtime itself; no network service dependency is visible in code.
- Project constraints emphasize script-driven gameplay iteration and headless script execution for generation tooling.

## 4. Component Map
| Component | Responsibility | Key Files | Depends On |
|---|---|---|---|
| World streaming | Spawn/despawn chunks around player and carry road continuity | `world/world_generator.gd`, `world/chunk_generator.gd` | Player position, noise, POI spawner |
| POI and spawn system | Weighted POI selection and spawning of buildings, loot, enemies | `world/poi_spawner.gd`, `world/poi_config.gd` | Scene resources, POI table |
| Procedural building interior | Expand rooms from elevator using occupancy-aware BFS | `world/building/building_generator.gd`, `world/building/room_node.gd` | Room templates under `world/building/rooms/` |
| Player and interaction | Character movement, inventory, placement mode, world interaction raycast | `player/player.gd`, `player/player_interact.gd` | Equipment/prop contracts, input actions |
| RV chassis and energy | Vehicle drive controls, fuel/power storage, wheel slots, refuel flow | `rv/chassis.gd`, `rv/fuel_filler.gd`, `rv/wheel_hitbox.gd` | Player item contracts, equipment generators |
| Equipment runtime | Shared base placement logic and concrete modules (generator/scrapper/crafting) | `equipment/equipment.gd`, `equipment/generator.gd`, `equipment/scrapper.gd`, `equipment/crafting_station.gd` | Connected RV contracts |
| Enemy AI | Wander/chase/attack loop and loot drop on death | `enemies/monster.gd`, `enemies/zombie.tscn` | Player group lookup, props |
| Energy tests | Contract tests for core fuel/power API and generator/refuel behavior | `tests/test_energy_system.gd` | `Chassis`, `Equipment`, `Generator` |

## 5. Runtime Flows
### Primary flow
1. `world/test_world.tscn` loads and instantiates `WorldGenerator`, `Player`, RV, and equipment props.
2. `WorldGenerator._ready()` seeds noise, creates a `POISpawner`, spawns behind/current/ahead chunks.
3. `WorldGenerator._process()` streams chunks by player Z distance.
4. `ChunkGenerator.generate_chunk()` builds terrain/road mesh, optionally places POI, then spawns loot/enemies.
5. Player interaction loop runs through `player/player_interact.gd` (E/F holds and quick interactions).
6. RV energy loop runs in `Chassis._physics_process()` via `step_energy_system()`, including generator contribution.

### Edge flow
1. Player uses full gas can on RV fuel filler.
2. `Chassis.refuel_from_player()` validates active item name and fuel capacity.
3. RV fuel increases, active can is consumed, empty can item is returned.
4. If can is empty or tank full, operation exits without consumption.

## 6. Data and State Model
- World stream state: `active_chunks`, `next_transform`, `next_turn_angle`.
- Chunk-local generation state: Bezier road controls, POI flags, terrain mesh data.
- Player state: inventory array (max 6), active slot, `has_large_item`, health/cooldowns, placement state.
- RV state: `current_fuel/max_fuel`, `current_power/max_power`, wheel slot occupancy, storage inventory.
- Enemy state: AI state enum, target pointer, health, cooldown timers.

## 7. Interfaces and Contracts
- Interactable item contract: objects implement `interact(player)`.
- Hold-interact contract: objects expose `interact_hold(player)` and `hold_timer`.
- Wheel install contract: target exposes `install_wheel() -> bool`.
- RV contract used by equipment: has methods `consume_power`, `add_item`, `deduct_materials`, and group `rv`.
- Generator contract used by chassis: nodes in group `rv_power_generators` with `get_connected_rv()` and `generate_power(rv, delta)`.
- Test contract verifies `Chassis` API methods and behavior (`consume_fuel`, `add_power`, `step_energy_system`, `refuel_from_player`).

## 8. Configuration and Environment
- `project.godot`:
  - `run/main_scene="res://world/test_world.tscn"`
  - physics engine set to Jolt.
  - renderer set to `gl_compatibility`.
- Runtime tuning is primarily via exported GDScript variables in modules.

## 9. Error Handling and Reliability
- Defensive guard checks are common (`has_method`, null checks, early returns).
- Missing POI scenes are filtered and warned by `POISpawner`.
- Resource clamping in `Chassis` prevents fuel/power overflow/underflow.
- Several gameplay paths rely on duck typing, increasing flexibility but reducing compile-time guarantees.

## 10. Security and Privacy Notes
- No network I/O or user credential handling is present in current gameplay scripts.
- Primary risk surface is gameplay state integrity, not data privacy.

## 11. Performance Notes
- Terrain mesh generation per chunk (`RESOLUTION = 80`) and collision mesh generation are likely hot paths.
- Chunk streaming currently depends on distance thresholds and may spike if generation stalls.
- Recursive node scans (loot spawn points, RV parent discovery) are acceptable at current scale but should be profiled for larger scenes.

## 12. Observability and Debugging
- Runtime uses `print()` and `push_warning()` for diagnostics in key flows.
- Headless test script `tests/test_energy_system.gd` provides pass/fail console output.
- No centralized logging or metrics pipeline exists yet.

## 13. Testing Strategy and Coverage Map
| Area | Existing Tests | Missing Tests | Priority |
|---|---|---|---|
| RV fuel/power API | `tests/test_energy_system.gd` | Additional edge cases for negative/zero deltas and integration with vehicle physics | High |
| Generator behavior | `tests/test_energy_system.gd` | Multi-generator interaction and concurrent consumers | High |
| Player interaction | None | Hold/release timing, wheel install, placement cancel/confirm | High |
| World generation | None | Chunk streaming boundaries, POI placement validity, missing scene fallback | High |
| Enemy AI/combat | None | State transitions, damage cooldown interactions, loot consistency | Medium |
| Building generation | None | Room occupancy, door sealing, deterministic seeded runs | Medium |

## 14. Operations Notes
- Run game:
  - `godot --path . res://world/test_world.tscn`
- Run generation scripts headlessly:
  - `godot --headless -s <script.gd>`
- Run Python offline tools:
  - `uv run main.py`
  - `uv run test_building_gen.py`

## 15. Risks and Open Questions
- Risk: Interaction and placement systems are timing-sensitive and currently untested.
- Risk: Procedural generation relies on many scene resources; missing assets reduce content variety.
- Risk: World generation and collision creation could become CPU-heavy without pooling/caching.
- Open question: What is the intended persistence model for RV inventory and world state?
- Open question: Which systems are expected to be authoritative in future co-op implementation?

## 16. Glossary
- Chunk: One streamed world segment generated by `ChunkGenerator`.
- POI: Point of interest with building, loot, and enemy spawn rules.
- RV: Player vehicle that stores resources and powers equipment.
- Equipment placement: Player-driven process that repositions an equipment node with ghost preview.
- Large item: Inventory item that locks slot switching until dropped.

## 17. Source Files Used
- `project.godot`
- `AGENTS.md`
- `world/test_world.tscn`
- `world/world_generator.gd`
- `world/chunk_generator.gd`
- `world/poi_spawner.gd`
- `world/poi_config.gd`
- `world/building/building_generator.gd`
- `world/building/room_node.gd`
- `player/player.gd`
- `player/player_interact.gd`
- `rv/chassis.gd`
- `equipment/equipment.gd`
- `equipment/generator.gd`
- `enemies/monster.gd`
- `tests/test_energy_system.gd`

## 18. Completeness Report
Generated docs set for initialization:
- `docs/architecture.md`
- `docs/design/gameplay-loop-and-balance.md`
- `docs/design/procedural-generation-and-content.md`
- `docs/modules/world-generation.md`
- `docs/modules/player-and-interaction.md`
- `docs/modules/rv-energy-and-equipment.md`
- `docs/knowledge/dev-runtime-and-test-commands.md`
- `docs/knowledge/godot-project-conventions.md`

Coverage decisions:
- Prioritized high-impact runtime systems (world, player interaction, RV energy).
- Captured both design intent and implementation contracts.

Unknowns and assumptions:
- Assumed this branch is a single-player gameplay prototype despite co-op project framing.
- Assumed no hidden CI or packaging requirements outside visible repo files.

Follow-up recommendations:
- Add automated tests for interaction timing and chunk generation boundaries.
- Add a dedicated doc once save/progression architecture exists.
