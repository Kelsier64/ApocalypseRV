# Module: World Generation

## 1. Responsibility
The world generation module streams traversable road chunks around the player, shapes terrain, and populates points of interest (POIs) with buildings, loot, and enemies.

## 2. Boundaries and Dependencies
- Owns runtime chunk lifecycle and per-chunk mesh generation.
- Delegates POI selection/spawning to `POISpawner`.
- Delegates procedural interior generation to `BuildingGenerator` for procedural POIs.
- Depends on player position to decide streaming cadence.
- Depends on scene assets listed in POI configuration.

## 3. Entry Points and Public Surface
- `WorldGenerator._ready()` initializes noise and initial chunks.
- `WorldGenerator._process(delta)` triggers spawn/despawn by distance.
- `ChunkGenerator.generate_chunk(start_transform, next_turn_angle, shared_noise, shared_detail_noise, shared_poi_spawner) -> Transform3D` builds one chunk and returns next start transform.
- `POISpawner.pick_poi() -> Dictionary` weighted POI selection.
- `POISpawner.spawn_building(poi, parent_node, local_pos)`, `spawn_loot(poi, parent_node, center, building)`, and `spawn_enemies(poi, parent_node, center, get_height)` perform content placement.

## 4. Internal Structure
| Part | Role | Key Symbols | File |
|---|---|---|---|
| Streaming coordinator | Maintains chunk window around player | `CHUNKS_AHEAD`, `CHUNKS_BEHIND`, `_spawn_next_chunk` | `world/world_generator.gd` |
| Chunk builder | Terrain and road mesh generation plus optional POI placement | `generate_chunk`, `_build_terrain_mesh`, `_build_road_mesh`, `_try_place_poi` | `world/chunk_generator.gd` |
| POI dispatcher | Selects POIs and spawns associated content | `pick_poi`, `spawn_building`, `spawn_loot`, `spawn_enemies` | `world/poi_spawner.gd` |
| Static POI config | Defines POI table weights and loot/enemy rules | `POI_TABLE` | `world/poi_config.gd` |
| Procedural interior | Generates room graph from elevator anchor | `generate`, `can_place_room`, `reserve_cells` | `world/building/building_generator.gd` |

## 5. Control Flow
### Main flow
1. `WorldGenerator` initializes FastNoiseLite fields and POI spawner.
2. Initial behind/current/ahead chunks are generated.
3. Each spawned chunk computes Bezier road and terrain mesh/collision.
4. With 50 percent probability, chunk attempts POI placement with road-distance constraint.
5. If POI valid, spawner instantiates building and optional loot/enemies.
6. `active_chunks` tracks boundaries; old chunks are freed behind player.

### Error flow
1. Missing player reference in world generator causes `_process()` early return.
2. Missing or invalid POI scenes are skipped in selection and may emit warnings.
3. Failed procedural script load results in no procedural building instance.
4. If no valid room candidate fits during building expansion, the door is sealed.

## 6. Data Contracts
- `POIConfig.POI_TABLE` entries include:
  - `id`, `scene`, `type`, `weight`, `footprint_radius`, `footprint_blend`, `min_road_distance`.
  - nested `loot` and `enemies` dictionaries.
  - optional `procedural_config` for procedural POIs.
- `RoomNode` contract for room templates:
  - `room_name`, `weight`, `grid_size`, `doors`.
- Height callback contract for enemy spawns:
  - `spawn_enemies(poi, parent_node, center, get_height: Callable)` expects a callable returning local Y.

## 7. Configuration Touchpoints
- `world/world_generator.gd`: `CHUNKS_AHEAD`, `CHUNKS_BEHIND`, noise parameters.
- `world/chunk_generator.gd`: constants for `CHUNK_SIZE`, `RESOLUTION`, `ROAD_WIDTH`.
- `world/poi_config.gd`: content weights and count ranges.
- `world/building/building_generator.gd`: exported `max_rooms`, `seed_value`.

## 8. Failure Modes and Safeguards
- Scene existence checks prevent hard crashes in POI selection.
- Mesh and collision are generated every chunk; missing assets reduce content but keep world functional.
- Building generation tracks occupancy to avoid room overlap.
- Door sealing prevents unreachable open portals when no room match exists.

## 9. Testing and Verification
Existing tests:
- No dedicated automated tests for world generation currently.

Missing tests:
- Chunk spawn/despawn boundary behavior around threshold values.
- POI selection weighting and missing-scene fallback.
- Procedural room graph constraints with fixed seeds.

Quick verification commands:
- `godot --path . res://world/test_world.tscn`
- `godot --headless -s <chunk_or_building_debug_script.gd>`

## 10. Change Checklist
- [ ] API contract checked
- [ ] Backward compatibility checked
- [ ] Docs consistency checked
- [ ] Tests updated or justified

## 11. Source Files Used
- `world/test_world.tscn`
- `world/world_generator.gd`
- `world/chunk_generator.gd`
- `world/poi_spawner.gd`
- `world/poi_config.gd`
- `world/building/building_generator.gd`
- `world/building/room_node.gd`

## 12. Completeness Notes
This document covers runtime behavior and contracts of streaming, POI, and procedural room generation in the current implementation. It does not yet include profiling data or deterministic replay tooling.