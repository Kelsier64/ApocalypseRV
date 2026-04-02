# Architecture

## System Overview
- ApocalypseRV is a Godot 4.6 survival prototype where a first-person player drives and upgrades an RV while traversing an endlessly streamed procedural highway.
- Runtime behavior is scene-driven from `res://world/test_world.tscn` and primarily composed of player interaction, RV/equipment systems, world chunk generation, and enemy AI loops.
- Integration style is intentionally lightweight: Godot groups and duck-typed method contracts are used instead of rigid interface layers.

## Main Components and Responsibilities
- Player and interaction layer: input, movement, inventory, hold interactions, and placement controls (`player/player.gd`, `player/player_interact.gd`).
- RV and equipment layer: vehicle control, wheel lifecycle, shared material inventory, and machine interactions (`rv/chassis.gd`, `equipment/*.gd`).
- World generation layer: chunk streaming, procedural terrain/roads, POI selection and spawning (`world/world_generator.gd`, `world/chunk_generator.gd`, `world/poi_*.gd`).
- Procedural building layer: room graph generation from elevator anchor and room metadata contracts (`world/building/building_generator.gd`).
- Enemy combat layer: AI state machine, player damage, and loot drop pipeline (`enemies/monster.gd`).

## Data and Control Flow
- Control starts from scene initialization, then world generator boots initial chunks and continues streaming updates during `_process`.
- Player interaction ray drives most gameplay commands by invoking target methods (`interact`, `interact_hold`, `install_wheel`) based on object capabilities.
- RV inventory signal (`inventory_changed`) pushes material-state changes to tablet UI and crafting eligibility.
- Chunk generation pulls POI config data, then spawns buildings/loot/enemies; enemy AI later pulls player targets by group lookup.

## Key Architectural Decisions and Rationale
- Group-based discovery (`player`, `rv`, `monsters`, `crafting_stations`) minimizes hard scene-path coupling across modules.
- Duck typing (`has_method`, property checks) reduces script import coupling and allows interchangeable interactables.
- Runtime mesh generation allows infinite-feeling world traversal without authoring a massive static map.
- Equipment placement freezes physics and adds collision exceptions to prioritize stable RV behavior over physically realistic attachment.

## Constraints, Risks, and Open Questions
- Constraint: Jolt physics is sensitive to invalid collision/scale usage and requires careful collision exception handling for attached equipment.
- Constraint: no automated test harness currently exists, so reliability depends on manual runtime verification.
- Risk: POI table contains some scene paths without matching assets, causing partially populated POIs.
- Open question: production tracking source for streaming distance (exported `player` node vs RV/chassis node) should be standardized.
- Open question: fuel/power state exists but consumption/gameplay coupling is not yet implemented.

## 1. Purpose and Scope
- ApocalypseRV is a Godot 4.6 first-person survival prototype centered on RV driving, scavenging, and procedural world traversal.
- In scope: runtime game loop in `res://world/test_world.tscn`, RV systems, player interaction, equipment placement/crafting, enemies, and procedural chunk/POI generation.
- Out of scope: backend services, networking stack, account systems, deployment infrastructure, and production telemetry.

## 2. Goals and Non-Goals
### Goals
- Keep gameplay loop playable with low ceremony: spawn world, drive RV, loot props, craft basic resources, survive enemy contact.
- Use composable Godot nodes and duck-typed contracts (`has_method`, groups) to avoid hard compile-time dependencies across subsystems.
- Stream a large world incrementally through chunk generation instead of a prebuilt map.

### Non-Goals
- Deterministic fully reproducible worlds from one seed across every random path.
- Strictly typed module boundaries with explicit interface classes.
- Comprehensive automated testing or CI gating (none currently defined in repository).

## 3. System Context
- Runtime engine: Godot 4.6 with `GL Compatibility` renderer and `Jolt Physics` (`project.godot`).
- Main entry scene: `res://world/test_world.tscn` (`project.godot` `run/main_scene`).
- Physics constraints: CollisionShapes under Jolt should avoid non-uniform scale tweening; placement systems rely on collision exceptions.
- Data persistence: state is in-memory at runtime; no save/load pipeline is implemented in scanned files.

## 4. Component Map
| Component | Responsibility | Key Files | Depends On |
|---|---|---|---|
| Test World Composition | Bootstraps player, RV, interactables, world generator | `world/test_world.tscn` | Godot scene loader |
| Player Core | Movement, camera, inventory, placement mode, health/death | `player/player.gd`, `player/player.tscn` | Input, equipment contracts, UI scripts |
| Player Interaction Ray | E/F hold interactions, quick pickup, wheel install | `player/player_interact.gd` | RayCast collisions, duck-typed target methods |
| RV Chassis | Vehicle control, wheel slot lifecycle, RV inventory, fuel/power state | `rv/chassis.gd`, `rv/chassis.tscn`, `rv/new_rv.tscn` | VehicleBody3D, wheel hitbox, props |
| Equipment Base + Devices | Generic placement flow and specialized station/seat/scrapper/tablet logic | `equipment/equipment.gd`, `equipment/*.gd` | Player placement API, RV group lookup |
| Props | Pickup and scrapping metadata contract | `props/interactable_item.gd`, `props/wheel.gd`, `props/*.tscn` | Player `add_item`, scrapper |
| World Streaming | Manage active chunk list and spawn/despawn based on tracked node Z | `world/world_generator.gd` | Chunk generator, POI spawner |
| Chunk + POI Pipeline | Build terrain/road meshes and populate POI loot/enemies | `world/chunk_generator.gd`, `world/poi_spawner.gd`, `world/poi_config.gd` | Noise, POI table, enemy scenes |
| Procedural Building | Elevator-rooted BFS room graph and door sealing | `world/building/building_generator.gd`, `world/building/room_node.gd` | Room scenes metadata |
| Enemy AI | Wander/chase/attack loop and loot drop | `enemies/monster.gd`, `enemies/zombie.tscn` | Player group lookup, prop scenes |

## 5. Runtime Flows
### Primary flow
1. Engine loads `world/test_world.tscn`; player and world generator initialize.
2. `WorldGenerator` initializes noise/spawner and creates initial behind/current/ahead chunks.
3. Player uses `InteractRay` to pick props, hold E for interactions, and hold F to move equipment.
4. RV and attached equipment exchange materials through RV inventory APIs and signals.
5. Enemies spawned by chunks/POIs seek player and apply contact damage via duck-typed call.

### Edge flow
1. Player starts equipment placement but looks into empty sky: placement ghost is hidden and confirm is blocked.
2. Scrapper receives prop while not connected under an RV node: operation is rejected and prop is bounced.
3. POI selected with missing scene path: building spawn warns and returns null while chunk generation continues.

## 6. Data and State Model
- Player inventory: `Array[Dictionary]` with keys `name`, `is_large`, `scene_path`; max 6 slots; large item lock rule in active slot handling.
- RV inventory: `Dictionary` material counts keyed by item name; emits `inventory_changed(item_name, new_amount)` on updates.
- Wheel state: `installed_wheels` fixed 4-slot array mapped to front/rear left/right wheel metadata.
- Placement state: equipment tracks original transform/parent/materials and toggles `is_being_placed` plus collision layers/masks.
- World streaming state: `active_chunks` array of dictionaries (`node`, `start_z`, `end_z`) and evolving `next_transform`/`next_turn_angle`.
- Enemy state: finite state machine (`WANDER`, `CHASE`, `ATTACK`) with target pointer, cooldowns, and death flags.

## 7. Interfaces and Contracts
- Group contracts: `player`, `monsters`, `rv`, `chassis`, `crafting_stations` are key discovery mechanisms.
- Interaction contracts:
  - Pickup target: `interact(player)`.
  - Hold target: `interact_hold(player)` plus mutable `hold_timer` property.
  - Wheel install target: `install_wheel()`.
- RV contract for equipment/tablet/scrapper:
  - `add_item`, `has_materials`, `deduct_materials`, `get_all_items`, plus `inventory_changed` signal.
- Placement contract from player to equipment:
  - `start_placement(player)`, `confirm_placement(transform,parent)`, `cancel_placement()`, `get_half_extents()`, `get_bottom_face_correction()`.
- Collision layer convention in runtime scenes:
  - Layer 1: regular physics bodies.
  - Layer 2: interaction-only hitboxes (e.g., wheel removal hitbox) not intended for chassis physical collision.

## 8. Configuration and Environment
- Project config highlights in `project.godot`:
  - Main scene: `res://world/test_world.tscn`.
  - Renderer: `gl_compatibility` for desktop/mobile render method.
  - Physics engine: `Jolt Physics`.
  - Default viewport: 2080x1440.
- Noise configuration (world generator): terrain seed `1337`, detail seed `7331` with different frequencies/octaves.
- Runtime commands:
  - `godot --path . res://world/test_world.tscn`
  - `godot --headless -s <script.gd>`
- Offline Python tools via `uv run <script>`.

## 9. Error Handling and Reliability
- Defensive checks are mostly null/validity checks (`if not scene`, `if not rv`, `is_instance_valid`).
- Systems prefer continuing with degraded behavior rather than hard-failing (example: POI building missing scene still allows chunk generation).
- Cooldowns and guard clauses prevent repeated interaction spam in player and enemy logic.
- Known fragile points:
  - Wheel hitbox assumes fixed parent chain to find chassis.
  - Hardcoded player node paths in driver seat (`CollisionShape3D`, `Camera3D`).
  - Building door sealing logic has known mismatches in expected sealed doors.

## 10. Security and Privacy Notes
- No external network/API integration is present in scanned runtime scripts.
- No credential files or secret material handling paths are implemented in reviewed gameplay code.
- Trust model is local single-process gameplay; script contracts are open and duck-typed, so misconfigured scenes can call invalid methods at runtime.

## 11. Performance Notes
- Chunk generation builds terrain and road meshes at runtime with `SurfaceTool` and creates concave collision shapes; this is a hot path while driving.
- Streaming logic can continuously allocate/free chunk nodes; performance depends on generation/despawn cadence and player speed.
- Procedural building generation loads room scenes and runs BFS expansions per spawn; heavy POI frequency can spike frame time.
- Enemy AI currently does straightforward per-frame logic without expensive global searches except nearest-player lookup via group list.

## 12. Observability and Debugging
- Primary observability mechanism is `print()` logs (chunk spawn/despawn, combat hits, inventory updates, crafting/scrapping outcomes).
- No centralized logger, metrics, or tracing sink exists.
- Practical debug entrypoints:
  - `WorldGenerator` logs chunk lifecycle.
  - `Monster` logs damage/combat events.
  - `Chassis` logs inventory updates.
  - Equipment and tablet flows log placement/crafting/offline conditions.

## 13. Testing Strategy and Coverage Map
| Area | Existing Tests | Missing Tests | Priority |
|---|---|---|---|
| Player movement/inventory | None in repo | Automated gameplay and inventory state tests | High |
| RV drive/wheel lifecycle | None in repo | Wheel install/remove regression tests and drive-state transitions | High |
| Equipment placement safety | None in repo | Collision-exception regression checks on attach/cancel | High |
| World streaming and chunk lifecycle | None in repo | Long-run streaming stability and memory/perf checks | High |
| POI/building content validity | None in repo | Asset existence and placement validity checks for all POIs | Medium |
| Enemy AI/combat | None in repo | Attack cooldown, state transitions, vehicle hit behavior tests | Medium |

## 14. Operations Notes
- There is no build pipeline and no declared automated test suite.
- Day-to-day verification is manual in Godot editor (F5) and command-line scene run.
- Content generation helper scripts can be executed headless with Godot.
- Python scripts in repository should be run with `uv` per project rule.

## 15. Risks and Open Questions
- Risk: POI table includes scene paths not present in `world/building/scenes`, causing partial POI generation.
- Risk: Streaming boundaries use rough Z heuristics despite curved roads, which may produce edge-case spawn/despawn timing.
- Risk: Duck-typed contracts improve flexibility but delay integration errors to runtime.
- Open question: Intended tracked entity for world streaming in production scene (export name is `player`, but design intent references RV/chassis tracking).
- Open question: Fuel/power values exist on chassis but no consumption model is implemented yet.
- Open question: Scope and timeline for multiplayer/co-op systems described in design document but not present in runtime code.

## 16. Glossary
- Chunk: One procedurally generated world segment (terrain + road + optional POI).
- POI: Point of interest spawn package containing building/loot/enemy rules.
- RV: Player mobile base rooted at `Chassis` (`VehicleBody3D`).
- Equipment placement: Hold-F flow that detaches/moves rigid devices and reattaches with collision exceptions.
- Prop: Pickup/scrap item class (`Prop`) with optional `scrap_yields`.
- Hold interaction: E-key timer-based interaction path requiring `hold_timer` and `interact_hold`.

## 17. Source Files Used
- `AGENTS.md`
- `project.godot`
- `GDD.md`
- `world/test_world.tscn`
- `world/world_generator.gd`
- `world/chunk_generator.gd`
- `world/poi_config.gd`
- `world/poi_spawner.gd`
- `world/building/building_generator.gd`
- `world/building/room_node.gd`
- `world/building/elevator_platform.gd`
- `world/building/rooms/*.tscn`
- `world/building/scenes/*.tscn`
- `player/player.gd`
- `player/player_interact.gd`
- `player/inventory_ui.gd`
- `player/health_bar_ui.gd`
- `player/player.tscn`
- `rv/chassis.gd`
- `rv/wheel_hitbox.gd`
- `rv/chassis.tscn`
- `rv/new_rv.tscn`
- `equipment/equipment.gd`
- `equipment/driver_seat.gd`
- `equipment/rv_panel.gd`
- `equipment/scrapper.gd`
- `equipment/crafting_station.gd`
- `equipment/tablet_screen.gd`
- `equipment/tablet_ui.gd`
- `enemies/monster.gd`
- `enemies/zombie.tscn`
- `props/interactable_item.gd`
- `props/wheel.gd`
- `generate_store.gd`

## 18. Completeness Report
- Generated files:
  - `docs/architecture.md`
  - `docs/designs/overview.md`
  - `docs/knowledge/project-facts.md`
  - `docs/knowledges/cross-system-contracts.md`
  - `docs/knowledges/equipment-placement-and-physics.md`
  - `docs/knowledges/world-streaming-and-poi.md`
  - `docs/knowledges/inventory-and-crafting-loop.md`
  - `docs/module/player-and-interaction.md`
  - `docs/module/rv-and-equipment.md`
  - `docs/module/world-generation.md`
  - `docs/module/procedural-building.md`
  - `docs/module/enemy-ai-and-combat.md`
- Coverage decisions:
  - Prioritized runtime-critical modules (player interaction, RV/equipment, world generation, building generation, enemy combat).
  - Added cross-cutting knowledge docs for contracts, placement physics, procedural streaming, and inventory/crafting lifecycle.
- Unknowns and assumptions:
  - Multiplayer behavior in `GDD.md` is treated as aspirational because code evidence is absent.
  - Long-term persistence/save system is assumed not implemented within scanned files.
- Follow-up recommendations:
  - Add automated smoke checks for missing POI scene assets and interaction contracts.
  - Add runtime validation around duck-typed contracts to fail fast with actionable errors.
  - Add profiling pass for chunk generation and collision mesh cost under sustained driving.
