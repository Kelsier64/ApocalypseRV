# Module: World Generation

## 1. Responsibility
- Stream and maintain active world chunks around a tracked node.
- Generate chunk terrain/roads at runtime and populate POIs, loot, and enemies.
- Coordinate POI data-driven selection and scene instantiation.

## 2. Boundaries and Dependencies
- Boundaries:
  - Does not implement player controls, RV driving logic, or enemy AI internals.
  - Delegates procedural building internals to building module when POI type is procedural.
- Dependencies:
  - Shared noise objects, POI configuration table, and scene assets.
  - Enemy and prop scenes used by spawner.

## 3. Entry Points and Public Surface
- `WorldGenerator._ready()`, `_process(_delta)`, `_spawn_next_chunk()`
- `ChunkGenerator.generate_chunk(start_transform, next_turn_angle, shared_noise, shared_detail_noise, shared_poi_spawner) -> Transform3D`
- `POISpawner.pick_poi() -> Dictionary`
- `POISpawner.spawn_building`, `POISpawner.spawn_loot(poi, parent_node, center, building)`, `POISpawner.spawn_enemies`

## 4. Internal Structure
| Part | Role | Key Symbols | File |
|---|---|---|---|
| Streaming orchestrator | Active chunk lifecycle and spawn/despawn thresholds | `CHUNKS_AHEAD`, `CHUNKS_BEHIND`, `active_chunks` | `world/world_generator.gd` |
| Chunk content builder | Terrain/road mesh+collision and optional POI placement | `CHUNK_SIZE`, `_build_terrain_mesh`, `_build_road_mesh` | `world/chunk_generator.gd` |
| POI catalog | Weighted POI definitions and loot/enemy configs | `POI_TABLE` | `world/poi_config.gd` |
| POI spawner runtime | Weighted pick and instantiation of building/loot/enemies | `_create_gridmap`, `_create_procedural` | `world/poi_spawner.gd` |
| Scene utility script | Generates convenience store scene asset | `_init`, `_create_box_wall` | `generate_store.gd` |

## 5. Control Flow
### Main flow
1. World generator initializes noise/spawner and bootstraps behind/current/ahead chunks.
2. At runtime, player/tracked-node Z position is compared with chunk boundaries to spawn new chunk(s) and queue free old ones.
3. Each chunk generates Bezier road path, terrain/road meshes and collisions, then optionally POI content.
4. POI spawner instantiates building plus loot/enemy distribution from table definitions.
5. Loot spawn uses building `LootSpawns` `Marker3D` points when present; if none are found, it falls back to center+radius random placement.

### Error flow
1. Missing POI scene path or failed load emits warning; build step returns null and generation continues.
2. Enemy/loot scene load failure skips those spawns rather than stopping chunk generation.
3. If tracked `player` export is unset, world generator `_process` exits and no streaming updates occur.

## 6. Data Contracts
- `active_chunks` entries are dictionaries with `node`, `start_z`, `end_z`.
- POI dictionary expected keys:
  - `type`, `weight`, `min_road_distance`, `footprint_radius`, `footprint_blend`, and optional `loot`/`enemies` blocks.
- Loot table entries require `scene` and numeric `weight`.
- Enemy config requires scene path and count/radius ranges.
- Procedural POI config may include `min_rooms` and `max_rooms` consumed by building generator.

## 7. Configuration Touchpoints
- Streaming constants:
  - `CHUNKS_AHEAD = 3`, `CHUNKS_BEHIND = 2`, chunk length assumption `150.0`.
- Chunk constants:
  - `CHUNK_SIZE = 150.0`, `RESOLUTION = 80`, `ROAD_WIDTH = 15.0`, `ROAD_BLEND_DISTANCE = 12.0`, `MAX_HEIGHT = 60.0`.
- Noise settings:
  - Terrain seed `1337` low frequency FBM.
  - Detail seed `7331` higher frequency FBM.

## 8. Failure Modes and Safeguards
- Safeguards:
  - POI placement checks minimum road distance before accepting candidate.
  - Terrain footprint blend flattens POI area to reduce extreme placement mismatch.
  - Spawner caches loaded scenes to reduce repeated load overhead.
- Failure modes:
  - POI config can reference non-existent scenes, causing partial POI outcomes.
  - Concave collision generation on runtime meshes can be costly.
  - Streaming based on Z bounds may not perfectly map to curved-road distance intuition.

## 9. Testing and Verification
- Existing tests: none.
- Missing tests:
  - Long-run streaming stability and memory behavior.
  - POI asset validity and spawn distribution checks.
  - Terrain/road continuity and collision seam checks.
- Quick verification commands:
  - `godot --path . res://world/test_world.tscn`
  - `godot --headless -s generate_store.gd`

## 10. Change Checklist
- [ ] API contract checked
- [ ] Backward compatibility checked
- [ ] Docs consistency checked
- [ ] Tests updated or justified

## 11. Source Files Used
- `world/world_generator.gd`
- `world/chunk_generator.gd`
- `world/poi_config.gd`
- `world/poi_spawner.gd`
- `world/test_world.tscn`
- `world/building/scenes/*.tscn`
- `generate_store.gd`

## 12. Completeness Notes
- This module doc covers world streaming and POI pipeline behavior currently active in runtime scripts.
- Detailed procedural room-graph generation is documented separately in `docs/module/procedural-building.md`.
