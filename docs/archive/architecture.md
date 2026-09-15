# Architecture

## 1. Purpose and Scope
ApocalypseRV is a Godot 4.6 cooperative first-person survival game where players drive and maintain an RV while moving through procedurally generated highway chunks. Runtime scope in this baseline includes world streaming, chunk terrain/road/nav generation, POI spawning, RV energy and equipment systems, player traversal and interaction, and monster AI with climbing and combat.

In scope:
- Real-time chunk streaming and generation
- POI selection, placement, and content spawning
- RV chassis fuel and power economy
- RV equipment behaviors and terminal interactions
- Player locomotion, inventory, and interaction timing
- Monster navigation, climbing, and attack behavior

Out of scope:
- Network replication model
- Save/load persistence architecture
- Release export/deployment pipelines (test CI is configured)

## 2. Goals and Non-Goals
### Goals
- Keep the runtime loop drivable and continuous through chunk streaming.
- Maintain clear contracts between world generation, RV systems, and actor behaviors.
- Preserve test-defined behavior contracts for climbing and monster navigation.
- Keep docs split by independent concerns to reduce coupling and merge friction.

### Non-Goals
- Full design of future content progression or narrative systems.
- Deep performance tuning prescriptions without profiling evidence.
- Converting this baseline into an implementation roadmap.

## 3. System Context
- Engine/runtime: Godot 4.6 with GL Compatibility renderer and Jolt physics.
- Main runtime scene: [world/test_world.tscn](../world/test_world.tscn#L1).
- Main scene entry configured in [project.godot](../project.godot#L16).
- Core runtime domains:
  - World generation and streaming
  - RV core and equipment
  - Player traversal and interaction
  - Monster AI and combat

## 4. Component Map
| Component | Responsibility | Key Files | Depends On |
|---|---|---|---|
| Shared Contracts (core/) | Group-name constants, item-name constants, shared climb math, world-entity container | core/groups.gd, core/item_names.gd, core/climb_math.gd, core/world_entities.gd, core/rv_connection.gd | None (leaf utilities) |
| World Stream Orchestrator | Maintain ahead/behind chunk window, spawn/despawn lifecycle, far-behind entity cleanup | world/world_generator.gd | Chunk generator, player position, WorldEntities |
| Chunk Generator | Build terrain, road, nav mesh, optional POI content, ambient zombies | world/chunk_generator.gd | Shared noise, POISpawner |
| POI System | Weighted POI selection and building/loot/enemy spawning | world/poi_spawner.gd, world/poi_config.gd | POI table, scene assets |
| Procedural Building Generator | Build multi-room structures from room definitions | world/building/building_generator.gd, world/building/room_node.gd | Room scenes, occupancy grid |
| RV Chassis Core | Driving, fuel/power, inventory, wheel lifecycle, durability | rv/chassis.gd | Input, generator group, player interactions |
| RV Equipment Layer | Placement, power devices, terminals, seat, scrapper | equipment/equipment.gd and equipment/*.gd | RV connection via ancestry and group contracts |
| Player Traversal and Interaction | Movement and modes orchestrate inventory and placement modules | player/player.gd, player/player_inventory.gd, player/equipment_placement.gd, player/player_interact.gd | Equipment and prop interaction contracts |
| Monster AI | Actor physics/navigation coordinate with a separate selection policy | enemies/monster.gd, enemies/combat_targeting.gd | Navigation data, contact predicates, player/chassis/equipment targets |
| Behavior Tests | Validate climb and navigation/attack contracts | tests/test_player_climbing.gd, tests/test_monster_navigation.gd | Script API surfaces |

## 5. Runtime Flows
### Primary flow: world travel and encounter loop
1. Main scene loads and world generator initializes shared noise and POI spawner.
2. Initial behind/current/ahead chunks are generated.
3. As player moves along Z, generator spawns new chunks ahead and despawns old chunks behind.
4. Each chunk builds terrain, road, and navigation strip.
5. Some chunks place POIs and spawn building, loot, and enemies.
6. Ambient road zombies may spawn independently of POIs.

Primary references:
- [world/world_generator.gd](../world/world_generator.gd#L17)
- [world/chunk_generator.gd](../world/chunk_generator.gd#L33)
- [world/poi_spawner.gd](../world/poi_spawner.gd#L8)

### Edge flow: RV interaction, crafting, and energy loop
1. RV chassis executes physics input handling.
2. Energy accounting consumes fuel and updates power based on driving and generator contribution.
3. Equipment and terminals resolve connected RV through ancestry and consume RV power for actions.
4. Crafting terminal checks RV materials and routes spawn requests through connected crafting stations.

Primary references:
- [rv/chassis.gd](../rv/chassis.gd#L174)
- [equipment/generator.gd](../equipment/generator.gd#L10)
- [equipment/tablet_ui.gd](../equipment/tablet_ui.gd#L121)
- [equipment/crafting_station.gd](../equipment/crafting_station.gd#L14)

### Edge flow: climbing combat loop
1. Player and monster can enter climb locomotion under geometry/state gates.
2. Climb loops apply wall contact checks, separation grace, and abort rules.
3. Monster target selection differs by locomotion context and can use touch-based structure attacks while climbing.
4. Tests enforce contract-level expectations for helper methods and behavior gates.

Primary references:
- [player/player.gd](../player/player.gd)
- [enemies/monster.gd](../enemies/monster.gd)
- [tests/test_player_climbing.gd](../tests/test_player_climbing.gd#L1)
- [tests/test_monster_navigation.gd](../tests/test_monster_navigation.gd#L1)

## 6. Data and State Model
Core state domains:
- World streaming state: active chunk dictionary entries with node/start_z/end_z.
- Procedural generation state: shared terrain/detail noise and per-chunk Bezier path state.
- POI content state: weighted POI table entries and optional procedural_config payload.
- RV resource state: fuel, power, material inventory dictionary, wheel slot occupancy.
- Actor locomotion state:
  - Player: NORMAL vs CLIMBING.
  - Monster: AI state (WANDER/CHASE/ATTACK) and locomotion state (NORMAL/CLIMBING).

## 7. Interfaces and Contracts
Contract patterns used in this codebase:
- Group membership contracts (constants in [core/groups.gd](../core/groups.gd); runtime code must reference `Groups.*`, tests deliberately use raw strings to pin the values):
  - rv, chassis, equipment, monster_damageable, rv_power_generators, crafting_stations, player, monsters.
- Duck-typed method contracts:
  - Equipment resolves connected RV by checking methods like add_item and deduct_materials (result cached, invalidated on reparent).
  - Interaction adapters call interact or interact_hold when present.
- Test-defined behavioral contracts:
  - Climb helper availability and mantle helper removal checks. Shared climb math lives in [core/climb_math.gd](../core/climb_math.gd); the player/monster helpers are thin wrappers kept because tests pin their names.
- Monster navigation and attack gate helper surface checks.
- World-entity ownership contract ([core/world_entities.gd](../core/world_entities.gd)):
  - Static chunk content (terrain, POI buildings, scavenge loot) is chunk-owned and dies with the chunk.
  - Active entities (enemies, crafted outputs, dropped items) live in the shared WorldEntities container; WorldGenerator despawns them with the chunk distance rule.
- Player mode contract: top-level modes (NORMAL/PLACING/UI/SEATED/DEAD) are mutually exclusive; transitions go through `enter_*`/`exit_*` helpers on the player, and callers must respect refusals.

Representative files:
- [equipment/equipment.gd](../equipment/equipment.gd)
- [player/player_interact.gd](../player/player_interact.gd#L30)
- [tests/test_player_climbing.gd](../tests/test_player_climbing.gd#L32)
- [tests/test_monster_navigation.gd](../tests/test_monster_navigation.gd#L71)

## 8. Configuration and Environment
Runtime and environment settings:
- Main scene: [project.godot](../project.godot#L16)
- Renderer mode: GL Compatibility in [project.godot](../project.godot#L28)
- Physics engine: Jolt in [project.godot](../project.godot#L24)
- Main local run command documented in [CLAUDE.md](../CLAUDE.md)

Project-level development conventions include using uv for Python-side tools as documented in [CLAUDE.md](../CLAUDE.md).

## 9. Error Handling and Reliability
Current reliability approach is guard-heavy and runtime-conditional:
- Null and missing dependency guards in world streaming and equipment scripts.
- Scene existence filtering and once-per-path warnings in POI spawner.
- Resource and power gating before crafting and terminal actions.
- Climb abort paths for unsafe conditions.

Notable examples:
- [world/world_generator.gd](../world/world_generator.gd#L45)
- [world/poi_spawner.gd](../world/poi_spawner.gd#L163)
- [equipment/crafting_station.gd](../equipment/crafting_station.gd#L14)
- [player/player.gd](../player/player.gd)

## 10. Security and Privacy Notes
This baseline has no explicit network transport, authentication, or external account handling in the inspected runtime scripts. Security concerns are therefore mostly runtime integrity and unsafe assumptions in scene wiring.

Operational caution points:
- Heavy duck-typing and ancestry resolution can fail silently when hierarchy changes.
- Missing content assets can shift gameplay outcomes without hard failures.

## 11. Performance Notes
Potential hot paths:
- Chunk terrain mesh generation with 80x80 grid triangulation.
- Frequent chunk spawn/despawn operations based on player movement.
- Monster AI per-physics-frame behavior and navigation logic.

Potential bottlenecks to profile first:
- Terrain and road mesh build time in chunk generation.
- Navigation mesh generation per chunk.
- Monster AI scaling with many active enemies.

## 12. Observability and Debugging
Current observability is mostly print/push_warning/push_error based:
- World and chunk spawn/despawn print statements.
- POI missing scene warnings from spawner.
- Climb and navigation debug toggles in player and monster scripts.
- SceneTree tests print PASS or push_error FAIL summaries.

Key references:
- [world/world_generator.gd](../world/world_generator.gd#L20)
- [world/poi_spawner.gd](../world/poi_spawner.gd#L178)
- [player/player.gd](../player/player.gd)
- [enemies/monster.gd](../enemies/monster.gd)
- [tests/test_player_climbing.gd](../tests/test_player_climbing.gd#L145)

## 13. Testing Strategy and Coverage Map
| Area | Existing Tests | Missing Tests | Priority |
|---|---|---|---|
| Player climbing and moving RV integration | tests/test_player_climbing.gd, tests/test_player_climbing_runtime.gd, tests/test_moving_rv_climbing.gd | Severe rollovers, crowds, and extended wheel-driven gameplay | Medium |
| Monster navigation/combat helper contracts | tests/test_monster_navigation.gd | Multi-monster pathing stress and perf regression tests | High |
| World generation and POI behavior | tests/test_world_entities.gd, tests/test_poi_resources.gd | Deterministic chunk generation and POI distribution checks | High |
| RV fuel/power and equipment interactions | tests/test_equipment_lifecycle.gd | Resource accounting and terminal workflow tests | High |

## 14. Operations Notes
Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1` for import checks, all test suites, and a 120-frame main-scene smoke test. GitHub Actions uses the same runner. Logs are under `.godot/test-logs/`.

Primary local commands:
- Run game scene:
  - godot --path . res://world/test_world.tscn
- Run headless generation script:
  - godot --headless -s <script.gd>
- Run behavior tests:
  - godot --headless --path . -s tests/<test>.gd

References:
- [CLAUDE.md](../CLAUDE.md)

## 15. Risks and Open Questions
1. POI content mismatch risk:
- Configured POI scene paths are checked by tests. Missing placeholder entries were removed; new entries must include existing assets.
- Evidence: [world/poi_config.gd](../world/poi_config.gd), [world/building/scenes](../world/building/scenes)

2. Equipment hierarchy coupling:
- Equipment online state depends on ancestry-based RV resolution and may vary by scene placement/reparenting. The lookup result is now cached and invalidated on reparent, but the contract is still hierarchical.
- Evidence: [equipment/equipment.gd](../equipment/equipment.gd), [world/test_world.tscn](../world/test_world.tscn#L52)

Resolved since the baseline: world player wiring (now assigned in test_world.tscn with a group fallback), the _can_begin_climb test/runtime drift (helper implemented and wired into _try_start_climb), chassis-side generator scanning (generators push power to their own RV), and scene-root leakage of crafted/dropped items (WorldEntities container).

## 16. Glossary
- Chunk: A generated world segment containing terrain, road, nav region, and optional POI content.
- POI: Point of interest selected from weighted configuration, mapped to gridmap or procedural building.
- RV Core: Chassis-level driving, resource, durability, and wheel management logic.
- Equipment: Placeable or mounted interactive node that consumes/provides RV capabilities.
- Locomotion State: Actor movement mode (for this baseline, NORMAL or CLIMBING).
- Separation Grace: Short climb-contact continuity window before forced abort.

## 17. Source Files Used
- [project.godot](../project.godot)
- [CLAUDE.md](../CLAUDE.md)
- [world/test_world.tscn](../world/test_world.tscn)
- [world/world_generator.gd](../world/world_generator.gd)
- [world/chunk_generator.gd](../world/chunk_generator.gd)
- [world/poi_spawner.gd](../world/poi_spawner.gd)
- [world/poi_config.gd](../world/poi_config.gd)
- [world/building/building_generator.gd](../world/building/building_generator.gd)
- [world/building/room_node.gd](../world/building/room_node.gd)
- [world/building/elevator_platform.gd](../world/building/elevator_platform.gd)
- [rv/chassis.gd](../rv/chassis.gd)
- [rv/fuel_filler.gd](../rv/fuel_filler.gd)
- [rv/wheel_hitbox.gd](../rv/wheel_hitbox.gd)
- [equipment/equipment.gd](../equipment/equipment.gd)
- [equipment/generator.gd](../equipment/generator.gd)
- [equipment/driver_seat.gd](../equipment/driver_seat.gd)
- [equipment/scrapper.gd](../equipment/scrapper.gd)
- [equipment/crafting_station.gd](../equipment/crafting_station.gd)
- [equipment/tablet_screen.gd](../equipment/tablet_screen.gd)
- [equipment/tablet_ui.gd](../equipment/tablet_ui.gd)
- [equipment/rv_panel.gd](../equipment/rv_panel.gd)
- [player/player.gd](../player/player.gd)
- [player/player_interact.gd](../player/player_interact.gd)
- [props/interactable_item.gd](../props/interactable_item.gd)
- [enemies/monster.gd](../enemies/monster.gd)
- [tests/test_player_climbing.gd](../tests/test_player_climbing.gd)
- [tests/test_player_climbing_runtime.gd](../tests/test_player_climbing_runtime.gd)
- [tests/test_monster_navigation.gd](../tests/test_monster_navigation.gd)

## 18. Completeness Report
### Generated files in this docs initialization run
- [docs/architecture.md](architecture.md)
- [docs/design/world-generation-and-pois.md](design/world-generation-and-pois.md)
- [docs/design/world-generation-procedural-buildings.md](design/world-generation-procedural-buildings.md)
- [docs/design/rv-power-and-crafting.md](design/rv-power-and-crafting.md)
- [docs/design/rv-equipment-interactions.md](design/rv-equipment-interactions.md)
- [docs/design/climbing-and-combat-behavior.md](design/climbing-and-combat-behavior.md)
- [docs/design/player-interaction-flow.md](design/player-interaction-flow.md)
- [docs/modules/world-generation.md](modules/world-generation.md)
- [docs/modules/world-generation-poi-system.md](modules/world-generation-poi-system.md)
- [docs/modules/world-generation-procedural-building.md](modules/world-generation-procedural-building.md)
- [docs/modules/rv-systems.md](modules/rv-systems.md)
- [docs/modules/rv-systems-equipment.md](modules/rv-systems-equipment.md)
- [docs/modules/player-traversal-and-interaction.md](modules/player-traversal-and-interaction.md)
- [docs/modules/monster-ai.md](modules/monster-ai.md)

### Coverage decisions
- Included multiple design docs to separate world, RV/equipment, and actor behavior concerns.
- Included multiple module docs to split deep component contracts under each domain.
- Did not generate docs/knowledge content because no external reference corpus was used.

### Component split map
| Component | Owning Code Paths | Target Detail Doc | Status |
|---|---|---|---|
| World stream coordinator | world/world_generator.gd | docs/modules/world-generation.md | New |
| POI selection and spawn pipeline | world/poi_spawner.gd, world/poi_config.gd | docs/modules/world-generation-poi-system.md | New |
| Procedural building generation | world/building/building_generator.gd, world/building/room_node.gd, world/building/elevator_platform.gd | docs/modules/world-generation-procedural-building.md | New |
| RV core resources and drive loop | rv/chassis.gd | docs/modules/rv-systems.md | New |
| RV equipment contracts | equipment/equipment.gd, equipment/generator.gd, equipment/driver_seat.gd, equipment/scrapper.gd, equipment/crafting_station.gd, equipment/tablet_screen.gd, equipment/tablet_ui.gd, equipment/rv_panel.gd | docs/modules/rv-systems-equipment.md | New |
| Player traversal and interaction | player/player.gd, player/player_interact.gd, props/interactable_item.gd | docs/modules/player-traversal-and-interaction.md | New |
| Monster AI and combat | enemies/monster.gd | docs/modules/monster-ai.md | New |

### Unknowns and follow-ups
- Extend world tests to deterministic generation and POI distribution.
- Extend equipment lifecycle tests to full fuel accounting, crafting, and terminal workflows.
- Reduce per-frame monster group scans / physics queries once profiling shows they matter at scale.
