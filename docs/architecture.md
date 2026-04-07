# Architecture

## 1. Purpose and Scope
- This document defines the current executable architecture baseline for ApocalypseRV and supports implementation decisions and cross-module change impact analysis.
- Scope includes world streaming and POI generation, RV driving and energy systems, and player interaction/inventory/equipment placement/crafting flows.
- Out of scope includes multiplayer authority/network synchronization, long-term save systems, and full enemy AI architecture details not covered by the current evidence set.

## 2. Goals and Non-Goals
### Goals
- Maintain a long-running road-world loop with continuous streaming and POI exploration. (world/world_generator.gd:4, world/world_generator.gd:54, world/chunk_generator.gd:66)
- Maintain a dual-resource RV energy model (fuel/power) that supports both driving and equipment usage. (rv/chassis.gd:41, rv/chassis.gd:151, equipment/generator.gd:10)
- Maintain a first-person interaction and equipment placement pipeline so scavenging and onboard production remain sustainable. (player/player_interact.gd:8, equipment/equipment.gd:73, equipment/tablet_ui.gd:126)

### Non-Goals
- This document does not define final balance targets (for example, time-to-empty or time-to-full).
- This document does not specify implementation details for all GDD vision features (for example, full voice systems or sleep systems).

## 3. System Context
- Engine: Godot 4.6. (project.godot:17)
- Physics: Jolt Physics. (project.godot:27)
- Renderer: GL Compatibility. (project.godot:32)
- Main scene: res://world/test_world.tscn. (project.godot:16)
- Design context: the RV is the shared survival core and the world is a procedural road + POI space. (GDD.md:20, GDD.md:40)

## 4. Component Map
| Component | Responsibility | Key Files | Depends On |
|---|---|---|---|
| World Streaming | Spawns/despawns chunks based on player position and maintains front/back buffers | world/world_generator.gd | Chunk Generation, POI Spawning |
| Chunk Generation | Builds terrain/road meshes, controls road curvature/slope, and emits per-chunk navigation regions | world/chunk_generator.gd | Noise, POI Spawning |
| POI Spawning | Performs weighted POI selection, spawns building/loot/enemies, and handles cache/missing-scene fallback | world/poi_spawner.gd, world/poi_config.gd | POI Config, Building Generator |
| Procedural Building | Expands rooms with occupancy + BFS and builds procedural structures | world/building/building_generator.gd | Room Scenes |
| Enemy Locomotion AI | Patrol/chase/attack with navigation-agent steering fallback and anti-stuck repath recovery | enemies/monster.gd, enemies/zombie.tscn | Chunk navigation regions, player/structure targeting |
| RV Chassis & Energy | Integrates drive input, engine/brake behavior, fuel/power state and signals, and chassis durability under monster attacks | rv/chassis.gd | Generator, Driver Seat, Fuel Filler |
| Generator Equipment | Auxiliary conversion from fuel to power | equipment/generator.gd | RV Chassis API |
| Driver Seat | Switches player driving state and seat camera control | equipment/driver_seat.gd | RV Chassis API |
| Player Interaction | Raycast interactions, E/F hold-tap behavior, wheel install, and generic interactions | player/player_interact.gd | Player Inventory, Interactable Objects |
| Player Inventory & Placement | 6-slot inventory, large-item restrictions, and placement preview/confirm/cancel | player/player.gd, equipment/equipment.gd | World Raycast, RV Hierarchy |
| Crafting UI & Station | Displays RV resources, checks material/power constraints, and outputs crafted items | equipment/tablet_ui.gd, equipment/crafting_station.gd | RV Inventory/Power Contracts |

## 5. Runtime Flows
### Primary flow
1. After entering the main scene, WorldGenerator creates initial chunks and then streams/despawns chunks as the player moves. (world/world_generator.gd:16, world/world_generator.gd:54, world/world_generator.gd:61)
2. Chunk generation builds terrain/road meshes and a road-following `ChunkNavigationRegion` for AI path queries. (world/chunk_generator.gd:54, world/chunk_generator.gd:55, world/chunk_generator.gd:56, world/chunk_generator.gd:334, world/chunk_generator.gd:377)
3. Zombie monsters use `NavigationAgent3D` for patrol/chase steering when map data is ready; otherwise they fall back to direct steering, and stuck movement triggers bounded recovery with forced repath. (enemies/zombie.tscn:48, enemies/monster.gd:185, enemies/monster.gd:207, enemies/monster.gd:285, enemies/monster.gd:314, enemies/monster.gd:334, enemies/monster.gd:355)
4. The player scavenges and interacts through raycast; items move into player inventory and update held visuals. (player/player_interact.gd:29, props/interactable_item.gd:22, player/player.gd:76)
5. The player can hold F to enter equipment placement mode, then confirm stable parenting onto RV or scene nodes. (player/player_interact.gd:57, player/player.gd:227, equipment/equipment.gd:108)
6. After entering the driver seat, chassis logic runs energy steps each frame and applies engine/steering/brake behavior. (equipment/driver_seat.gd:45, rv/chassis.gd:205, rv/chassis.gd:151)
7. Tablet UI enables/disables crafting based on RV materials/power and routes successful outputs through Crafting Station. (equipment/tablet_ui.gd:116, equipment/tablet_ui.gd:126, equipment/crafting_station.gd:11)

### Edge flow
1. If a POI scene is missing, POISpawner filters or warns and world generation continues. (world/poi_spawner.gd:14, world/poi_spawner.gd:178)
2. If fuel is insufficient, chassis blocks drive force and applies brake fallback. (rv/chassis.gd:167, rv/chassis.gd:251)
3. If placement raycast does not hit a valid surface, placement confirmation is blocked. (player/player.gd:370)
4. If RV is disconnected, unpowered, missing materials, or no matching station exists, tablet crafting is blocked. (equipment/tablet_ui.gd:127, equipment/tablet_ui.gd:134, equipment/tablet_ui.gd:149)

## 6. Data and State Model
- World state
  - `active_chunks`: streaming state array with `{ node, start_z, end_z }`. (world/world_generator.gd:7)
  - `next_transform`, `next_turn_angle`: handoff state for the next chunk. (world/world_generator.gd:8, world/world_generator.gd:9)
- POI state
  - `POI_TABLE`: weighted POI definitions, footprint settings, loot/enemy rules, and procedural options. (world/poi_config.gd:4)
  - `POISpawner` caches: `_scene_cache` and `_missing_scene_warnings`. (world/poi_spawner.gd:4, world/poi_spawner.gd:5)
- RV state
  - `current_fuel/max_fuel`, `current_power/max_power`, with state changes emitted via signals. (rv/chassis.gd:41, rv/chassis.gd:43, rv/chassis.gd:33)
  - `inventory` as a material dictionary. (rv/chassis.gd:35)
- Player state
  - `inventory` (6 slots), `has_large_item`, `active_slot_index`. (player/player.gd:12, player/player.gd:13, player/player.gd:14)
  - `placing_equipment` and placement mode. (player/player.gd:19, player/player.gd:22)

## 7. Interfaces and Contracts
- World contracts
  - `ChunkGenerator.generate_chunk(start_transform, next_turn_angle, shared_noise, shared_detail_noise, shared_poi_spawner) -> Transform3D` returns the next chunk start transform. (world/chunk_generator.gd:33)
  - `ChunkGenerator._build_navigation_region()` creates road-following per-chunk `NavigationRegion3D` strips for AI pathing. (world/chunk_generator.gd:334, world/chunk_generator.gd:377)
  - `POISpawner.pick_poi() -> Dictionary|{}` and `spawn_building/spawn_loot/spawn_enemies` generate POI content from config. (world/poi_spawner.gd:8, world/poi_spawner.gd:31, world/poi_spawner.gd:49, world/poi_spawner.gd:84)
- Enemy locomotion contracts
  - `Monster._can_use_navigation()` and `Monster._get_navigation_direction(destination)` provide navigation-agent steering with direct-vector fallback. (enemies/monster.gd:285, enemies/monster.gd:314)
  - `Monster._update_stuck_watchdog(delta, moving_intent)` and `Monster._trigger_stuck_recovery()` gate bounded unstuck behavior through progress thresholds, cooldown, and short fallback windows. (enemies/monster.gd:334, enemies/monster.gd:350, enemies/monster.gd:355)
- RV contracts
  - `consume_fuel/add_fuel/consume_power/add_power/has_usable_power/step_energy_system/refuel_from_player`. (rv/chassis.gd:118, rv/chassis.gd:126, rv/chassis.gd:133, rv/chassis.gd:141, rv/chassis.gd:148, rv/chassis.gd:151, rv/chassis.gd:65)
  - `take_damage(amount)` applies chassis durability loss and can disable driving at zero durability. (rv/chassis.gd:75)
- Equipment contracts
  - `Equipment.start_placement/confirm_placement/cancel_placement`. (equipment/equipment.gd:73, equipment/equipment.gd:108, equipment/equipment.gd:138)
  - `Generator.generate_power(rv, delta)`. (equipment/generator.gd:10)
- Player contracts
  - `Player.add_item/get_active_item_name/consume_active_item`. (player/player.gd:37, player/player.gd:122, player/player.gd:127)
  - Interactable objects must expose `interact` or optionally `interact_hold`. (player/player_interact.gd:33, player/player_interact.gd:36)

## 8. Configuration and Environment
- Entry point: `run/main_scene = res://world/test_world.tscn`. (project.godot:16)
- World parameters: chunk buffer sizes and noise settings. (world/world_generator.gd:4, world/world_generator.gd:5, world/world_generator.gd:94)
- Driving/energy parameters: chassis and generator exported values. (rv/chassis.gd:3, rv/chassis.gd:46, equipment/generator.gd:3)
- Interaction parameters: player slot count, placement distance, and interaction timing thresholds. (player/player.gd:12, player/player.gd:20, player/player_interact.gd:21)

## 9. Error Handling and Reliability
- Missing POI resources follow a skip + warn-once strategy to avoid hard crashes. (world/poi_spawner.gd:14, world/poi_spawner.gd:178)
- Monster movement degrades gracefully: if navigation maps are not ready, steering falls back to direct vectors; if movement stalls beyond threshold, stuck recovery forces repath with cooldown to avoid infinite lock states. (enemies/monster.gd:314, enemies/monster.gd:318, enemies/monster.gd:334, enemies/monster.gd:350, enemies/monster.gd:355)
- Energy mutation paths are clamped and guarded against insufficient resources to avoid out-of-range states. (rv/chassis.gd:121, rv/chassis.gd:174, rv/chassis.gd:181)
- Equipment placement adds collision exceptions to reduce RV physics instability risk. (equipment/equipment.gd:123)
- Crafting uses layered gating (RV connectivity, materials, power, station validity) to reduce invalid output paths. (equipment/tablet_ui.gd:127, equipment/tablet_ui.gd:134, equipment/tablet_ui.gd:145)

## 10. Security and Privacy Notes
- The current evidence set does not include external network I/O, account authentication, or personal-data storage flows.
- The primary architecture-level risk is duck-typing contract drift causing runtime feature breakage, not conventional data-exposure risk. (equipment/equipment.gd:57, equipment/tablet_ui.gd:121)

## 11. Performance Notes
- Chunk generation builds mesh + collision each time and is a high-cost hotspot. (world/chunk_generator.gd:135, world/chunk_generator.gd:237, world/chunk_generator.gd:251)
- `POISpawner` uses scene caching to reduce repeated load cost. (world/poi_spawner.gd:4, world/poi_spawner.gd:153)
- Chassis polls the `rv_power_generators` group every frame; scalability should be monitored as equipment count grows. (rv/chassis.gd:195)

## 12. Observability and Debugging
- `print/push_warning/push_error` are currently the primary observability output paths. (world/world_generator.gd:19, world/poi_spawner.gd:178, tests/test_energy_system.gd:170)
- The energy test script provides a headless PASS/FAIL signal suitable for regression checks. (tests/test_energy_system.gd:165)

## 13. Testing Strategy and Coverage Map
| Area | Existing Tests | Missing Tests | Priority |
|---|---|---|---|
| RV energy and refueling | `tests/test_energy_system.gd` covers API and core behavior | Missing variable-framerate/extreme-value stress tests | High |
| World streaming and POI | No automation; currently manual verification | Missing chunk stability and POI weight-distribution tests | High |
| Enemy navigation and unstuck recovery | `tests/test_monster_navigation.gd` contract checks for navigation/fallback/stuck helper availability | Missing scene-level path quality and multi-obstacle traversal regression tests | High |
| Player interaction and equipment placement | No automation; currently manual verification | Missing interaction timing and placement parent-selection tests | High |
| Crafting flow | No dedicated test | Missing UI gating and station-connectivity contract tests | Medium |

## 14. Operations Notes
- Run game: `godot --path . res://world/test_world.tscn`
- Run headless generation script: `godot --headless -s <script.gd>`
- Python tooling (project rule): `uv run main.py` or `uv run test_building_gen.py`

## 15. Risks and Open Questions
- Risk: `POIConfig` references many scene paths; missing assets reduce content variety. (world/poi_config.gd:53, world/poi_spawner.gd:14)
- Risk: interaction and crafting rely on duck typing, so interface changes lack compile-time protection. (equipment/tablet_ui.gd:121, equipment/equipment.gd:57)
- Risk: world generation has no automated regression coverage, so later changes may introduce hidden degradation.
- Open question: should deterministic seeds + event logs be introduced for replayable tests?
- Open question: what are the target balance baselines for RV endurance and recharge speed?

## 16. Glossary
- Chunk: base streaming unit of the road world.
- POI: Point of Interest where players can stop and scavenge.
- RV: shared mobile base (chassis, equipment, energy systems).
- Placement Ghost: equipment placement preview state (semi-transparent, confirm/cancel).
- Duck Typing Contract: cross-module interaction by method/signal naming instead of explicit typed interfaces.

## 17. Source Files Used
- project.godot
- GDD.md
- docs/design/world-generation-and-poi.md
- docs/design/rv-energy-and-driving.md
- docs/design/player-interaction-and-equipment.md
- docs/modules/world-generation.md
- docs/modules/rv-chassis-energy.md
- docs/modules/player-equipment-interactions.md
- world/world_generator.gd
- world/chunk_generator.gd
- world/poi_spawner.gd
- world/poi_config.gd
- world/building/building_generator.gd
- rv/chassis.gd
- rv/fuel_filler.gd
- equipment/generator.gd
- equipment/driver_seat.gd
- player/player.gd
- player/player_interact.gd
- equipment/equipment.gd
- equipment/tablet_ui.gd
- equipment/crafting_station.gd
- props/interactable_item.gd
- tests/test_energy_system.gd

## 18. Completeness Report
- Generated files
  - docs/design/world-generation-and-poi.md
  - docs/design/rv-energy-and-driving.md
  - docs/design/player-interaction-and-equipment.md
  - docs/modules/world-generation.md
  - docs/modules/rv-chassis-energy.md
  - docs/modules/player-equipment-interactions.md
  - docs/architecture.md
- Coverage decisions
  - Covered three high-impact partitions: world generation, RV energy, and player interaction/equipment flow.
  - Did not create `docs/knowledge/*.md` because this initialization did not rely on external reference sources.
- Unknowns and assumptions
  - Networking synchronization, persistence, and detailed enemy AI architecture are not covered.
  - Balance target values are not yet documented.
- Follow-up recommendations
  - Add headless verification scripts for world streaming and POI behavior.
  - Add automated regression tests for interaction and crafting flows.
  - Consolidate duck-typing contracts into explicit interface docs and test fixtures.
