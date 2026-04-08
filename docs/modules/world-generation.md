# Module: World Generation

## Responsibility
- Maintain a continuously drivable road world through chunk streaming, and reclaim chunks that are far behind the player. (world/world_generator.gd:4, world/world_generator.gd:5, world/world_generator.gd:54, world/world_generator.gd:61)
- Build terrain, road, chunk-local navigation strips, POI content, and road-side enemies per chunk. (world/chunk_generator.gd:33, world/chunk_generator.gd:54, world/chunk_generator.gd:55, world/chunk_generator.gd:56, world/chunk_generator.gd:66, world/chunk_generator.gd:71, world/chunk_generator.gd:334, world/chunk_generator.gd:377, world/chunk_generator.gd:380)
- Manage POI selection/content strategy through `POIConfig` + `POISpawner`. (world/poi_config.gd:4, world/poi_spawner.gd:8, world/poi_spawner.gd:31)

## Boundaries
- This module includes `WorldGenerator`, `ChunkGenerator`, `POISpawner`, `POIConfig`, and the procedural POI integration point with `BuildingGenerator`. (world/world_generator.gd:1, world/chunk_generator.gd:2, world/poi_spawner.gd:2, world/poi_config.gd:2, world/building/building_generator.gd:2)
- This module excludes player controls, vehicle controls, and combat AI logic; it is responsible only for world-entity generation and initial placement. (world/world_generator.gd:44, world/poi_spawner.gd:84, enemies/monster.gd:160, enemies/monster.gd:201)
- This module owns navigation-surface generation for each chunk (`NavigationRegion3D` + `NavigationMesh` strip), while enemy steering/path selection remains in enemy scripts that consume those maps. (world/chunk_generator.gd:334, world/chunk_generator.gd:335, world/chunk_generator.gd:377, enemies/monster.gd:341, enemies/monster.gd:353)
- Startup boundary: main scene entry is `res://world/test_world.tscn` from project configuration. (project.godot:16)

## Entry points
- `WorldGenerator._ready()`: initializes noise/spawner and initial chunk buffers. (world/world_generator.gd:16, world/world_generator.gd:17, world/world_generator.gd:18, world/world_generator.gd:23, world/world_generator.gd:41)
- `WorldGenerator._process(_delta)`: decides chunk add/remove behavior from player position. (world/world_generator.gd:44, world/world_generator.gd:48, world/world_generator.gd:54, world/world_generator.gd:61)
- `ChunkGenerator.generate_chunk(start_transform, next_turn_angle, shared_noise, shared_detail_noise, shared_poi_spawner)`: generates one chunk and returns the next chunk start transform. (world/chunk_generator.gd:33, world/chunk_generator.gd:73)
- `POISpawner.pick_poi()/spawn_*`: handles POI selection and content placement. (world/poi_spawner.gd:8, world/poi_spawner.gd:31, world/poi_spawner.gd:49, world/poi_spawner.gd:84)

## Internal structure table
| Unit | Type | Key state | Main methods | Notes |
|---|---|---|---|---|
| `WorldGenerator` | `Node3D` script | `active_chunks`, `next_transform`, `next_turn_angle`, `terrain_noise`, `detail_noise`, `poi_spawner` | `_ready`, `_process`, `_spawn_next_chunk`, `_init_noise` | Manages world streaming and shared noise/POI spawner state. (world/world_generator.gd:7, world/world_generator.gd:8, world/world_generator.gd:9, world/world_generator.gd:10, world/world_generator.gd:11, world/world_generator.gd:16, world/world_generator.gd:44, world/world_generator.gd:66, world/world_generator.gd:92) |
| `ChunkGenerator` | `Node3D` class | Road curve control points, POI state, shared noise references | `generate_chunk`, `_try_place_poi`, `_build_terrain_mesh`, `_build_road_mesh`, `_build_navigation_region`, `_spawn_road_zombies` | Core per-chunk geometry/content generation center. (world/chunk_generator.gd:2, world/chunk_generator.gd:12, world/chunk_generator.gd:16, world/chunk_generator.gd:33, world/chunk_generator.gd:75, world/chunk_generator.gd:135, world/chunk_generator.gd:251, world/chunk_generator.gd:334, world/chunk_generator.gd:385) |
| `POISpawner` | `RefCounted` class | `_scene_cache`, `_missing_scene_warnings` | `pick_poi`, `spawn_building`, `spawn_loot`, `spawn_enemies` | Handles POI resource selection, scene cache, and fallback behavior. (world/poi_spawner.gd:2, world/poi_spawner.gd:4, world/poi_spawner.gd:5, world/poi_spawner.gd:8, world/poi_spawner.gd:31, world/poi_spawner.gd:49, world/poi_spawner.gd:84) |
| `POIConfig` | `RefCounted` config holder | `POI_TABLE` | N/A (data-only) | POI distribution and loot/enemy configuration source. (world/poi_config.gd:2, world/poi_config.gd:4) |
| `BuildingGenerator` | `Node3D` class | `max_rooms`, `occupied_cells`, `room_defs` | `_build_room_defs`, `generate`, `can_place_room`, `reserve_cells` | Dynamically attached by spawner for procedural POIs. (world/building/building_generator.gd:2, world/building/building_generator.gd:6, world/building/building_generator.gd:10, world/building/building_generator.gd:15, world/poi_spawner.gd:121, world/poi_spawner.gd:128) |

## Control flow
1. `_ready` initializes two `FastNoiseLite` instances and a `POISpawner`, then creates behind/current/ahead chunk buffers. (world/world_generator.gd:17, world/world_generator.gd:18, world/world_generator.gd:23, world/world_generator.gd:41)
2. `_spawn_next_chunk` runs `generate_chunk` via `chunk_generator.gd`, uses returned transform as next start, and randomizes the next turn angle. (world/world_generator.gd:66, world/world_generator.gd:68, world/world_generator.gd:72, world/world_generator.gd:86, world/world_generator.gd:88)
3. `generate_chunk` builds a Bezier road, generates terrain/road meshes, then calls `_build_navigation_region()` to attach a road-following `NavigationRegion3D` strip before computing end transform. (world/chunk_generator.gd:43, world/chunk_generator.gd:54, world/chunk_generator.gd:55, world/chunk_generator.gd:56, world/chunk_generator.gd:334, world/chunk_generator.gd:377)
4. Still inside `generate_chunk`, POI content generation runs when present, and `_spawn_road_zombies()` is invoked for ambient road enemies after generation. (world/chunk_generator.gd:66, world/chunk_generator.gd:67, world/chunk_generator.gd:68, world/chunk_generator.gd:71, world/chunk_generator.gd:385)
5. Every frame, chunk boundaries are compared against player z to decide forward spawning and old-chunk reclamation. (world/world_generator.gd:48, world/world_generator.gd:52, world/world_generator.gd:54, world/world_generator.gd:59, world/world_generator.gd:61, world/world_generator.gd:62)

## Data contracts
- `active_chunks` element contract (`WorldGenerator`):
  - shape: `{ "node": Node3D, "start_z": float, "end_z": float }`. (world/world_generator.gd:7, world/world_generator.gd:30, world/world_generator.gd:79)
- Chunk navigation strip contract (`ChunkGenerator`):
  - `_build_navigation_region()` configures `NavigationMesh` agent parameters and builds a two-triangle strip per segment over a Bezier-sampled road corridor (`nav_segments=44`, width derived from `ROAD_WIDTH * 0.9`). (world/chunk_generator.gd:334, world/chunk_generator.gd:336, world/chunk_generator.gd:337, world/chunk_generator.gd:338, world/chunk_generator.gd:341, world/chunk_generator.gd:342, world/chunk_generator.gd:374, world/chunk_generator.gd:375)
  - The generated region is attached as `ChunkNavigationRegion`; creation is skipped when fewer than 4 nav vertices are produced. (world/chunk_generator.gd:365, world/chunk_generator.gd:377, world/chunk_generator.gd:378, world/chunk_generator.gd:380)
- Monster navigation consumer contract:
  - `enemies/zombie.tscn` provides a `NavigationAgent3D` child consumed by `Monster` through `get_node_or_null("NavigationAgent3D")`, with desired-distance tuning in `_ready`. (enemies/zombie.tscn:48, enemies/zombie.tscn:49, enemies/zombie.tscn:50, enemies/monster.gd:78, enemies/monster.gd:86, enemies/monster.gd:87)
  - Patrol/chase steering calls `_get_navigation_direction()`, which uses nav pathing only when `_can_use_navigation()` validates the navigation map; otherwise steering falls back to direct movement. (enemies/monster.gd:160, enemies/monster.gd:185, enemies/monster.gd:201, enemies/monster.gd:205, enemies/monster.gd:341, enemies/monster.gd:348, enemies/monster.gd:351, enemies/monster.gd:353, enemies/monster.gd:359, enemies/monster.gd:368)
  - Navigation helper surface is exercised by the partition test script (`_can_use_navigation`, `_get_navigation_direction`, `_compute_fallback_direction`, `_should_use_navigation_for_chase`, and related stuck/elevation helpers), which acts as the module's explicit behavior contract for enemy-navigation consumption of generated chunk nav maps. (tests/test_monster_navigation.gd:37, tests/test_monster_navigation.gd:38, tests/test_monster_navigation.gd:39, tests/test_monster_navigation.gd:209, tests/test_monster_navigation.gd:238, tests/test_monster_navigation.gd:260)
- `POIConfig.POI_TABLE` entry contract:
  - required/observed keys: `id`, `scene`, `type`, `weight`, `footprint_radius`, `footprint_blend`, `min_road_distance`, `loot`, `enemies`. (world/poi_config.gd:6, world/poi_config.gd:7, world/poi_config.gd:8, world/poi_config.gd:9, world/poi_config.gd:10, world/poi_config.gd:11, world/poi_config.gd:12, world/poi_config.gd:13, world/poi_config.gd:22)
  - `loot` contract: `count: Vector2i`, `radius: float`, `table: [{scene, weight}]`. (world/poi_config.gd:14, world/poi_config.gd:15, world/poi_config.gd:16, world/poi_config.gd:17)
  - `enemies` contract: `count: Vector2i`, `radius: float`, `scene: String`. (world/poi_config.gd:23, world/poi_config.gd:24, world/poi_config.gd:25)
  - procedural extension: `type="procedural"` + `procedural_config.min_rooms/max_rooms`. (world/poi_config.gd:145, world/poi_config.gd:150, world/poi_config.gd:151, world/poi_config.gd:152)
- `POISpawner` function contracts:
  - `pick_poi()` returns `Dictionary` or `{}`; returns empty when valid entries are absent or total weight is invalid. (world/poi_spawner.gd:8, world/poi_spawner.gd:19)
  - `spawn_building` accepts `poi/parent/local_pos` and may return `null`. (world/poi_spawner.gd:31, world/poi_spawner.gd:32, world/poi_spawner.gd:34)
  - `spawn_enemies` uses `Callable get_height` to fetch ground height and spawn at +2.0m offset. (world/poi_spawner.gd:84, world/poi_spawner.gd:103)

## Config touchpoints
- Main scene setting: `run/main_scene = res://world/test_world.tscn`. (project.godot:16)
- Engine/render settings affect generation presentation and collision behavior (Jolt + GL compatibility). (project.godot:27, project.godot:32, project.godot:33)
- World noise parameters: seed/frequency/fractal settings are defined in `_init_noise`. (world/world_generator.gd:94, world/world_generator.gd:96, world/world_generator.gd:103, world/world_generator.gd:105)
- Content distribution parameters: `POI_TABLE` weights and radius-related fields directly influence spawn probability and density. (world/poi_config.gd:9, world/poi_config.gd:10, world/poi_config.gd:12)

## Failure modes
- `player` not bound: world streaming updates do not run (no forward push, no reclamation). (world/world_generator.gd:45)
- Navigation strip early-exit: `_build_navigation_region()` returns without creating a region when nav vertex count is too small (`< 4`), leaving that chunk without generated navigation polygons. (world/chunk_generator.gd:365, world/chunk_generator.gd:366)
- Monster navigation fallback: when `NavigationAgent3D` is missing/invalid or map iteration is not ready, steering downgrades to direct vectors, which preserves movement but can reduce obstacle-aware pathing. (enemies/monster.gd:341, enemies/monster.gd:344, enemies/monster.gd:346, enemies/monster.gd:349, enemies/monster.gd:351, enemies/monster.gd:353, enemies/monster.gd:368)
- Missing POI scenes: gridmap entries are skipped and load failures emit warnings. (world/poi_spawner.gd:14, world/poi_spawner.gd:153, world/poi_spawner.gd:178)
- Empty POI content config: `loot` or `enemies` generation paths are skipped directly. (world/poi_spawner.gd:51, world/poi_spawner.gd:56, world/poi_spawner.gd:87)
- Excessive road cross-slope: height difference is clamped, which avoids over-tilt but may create local visual mismatch between road and terrain. (world/chunk_generator.gd:278, world/chunk_generator.gd:282, world/chunk_generator.gd:285)

## Testing
- Automated verification:
  - `tests/test_monster_navigation.gd` runs as a headless `SceneTree` contract script targeting the enemy-navigation helper surface consumed by this module's chunk navigation output, but current helper API drift should be reconciled before treating it as a green gate. (tests/test_monster_navigation.gd:1, tests/test_monster_navigation.gd:6, tests/test_monster_navigation.gd:37, tests/test_monster_navigation.gd:40, enemies/monster.gd:1120)
- Executable manual verification:
  - Enter main scene and move forward to confirm continuous chunk generation and rear chunk reclamation. (project.godot:16, world/world_generator.gd:54, world/world_generator.gd:61)
  - Inspect a generated chunk and verify a `ChunkNavigationRegion` child exists with a road-following navigation strip. (world/chunk_generator.gd:56, world/chunk_generator.gd:334, world/chunk_generator.gd:377, world/chunk_generator.gd:378, world/chunk_generator.gd:380)
  - Validate zombie navigation dependency: confirm `NavigationAgent3D` exists in the zombie scene and patrol/chase movement calls navigation steering helpers. (enemies/zombie.tscn:48, enemies/monster.gd:78, enemies/monster.gd:185, enemies/monster.gd:205, enemies/monster.gd:353)
  - Validate wall-climb behavior: place an active target at least `wall_climb_min_target_height_gap` above the monster behind a near-vertical wall, then confirm short climb bursts apply upward/forward velocity and stop after cooldown is armed. (enemies/monster.gd:34, enemies/monster.gd:35, enemies/monster.gd:36, enemies/monster.gd:370, enemies/monster.gd:395, enemies/monster.gd:399, enemies/monster.gd:417, enemies/monster.gd:418, enemies/monster.gd:419, enemies/monster.gd:414)
  - Check POI frequency/content distribution against `POI_TABLE` weights and count/radius ranges. (world/chunk_generator.gd:50, world/poi_spawner.gd:22, world/poi_spawner.gd:54, world/poi_spawner.gd:90)
  - For procedural POIs, verify `max_rooms` falls within config range and triggers BuildingGenerator output. (world/poi_spawner.gd:121, world/poi_spawner.gd:128, world/poi_spawner.gd:129, world/poi_spawner.gd:130, world/building/building_generator.gd:66)
- Unknown: this evidence set does not include an automated scene-level world-streaming/POI integration test; chunk/POI runtime behavior verification remains manual.

## Change checklist
- When adding/changing POIs:
  - Keep `POIConfig.POI_TABLE` field integrity (`weight`, `min_road_distance`, `loot`, `enemies`). (world/poi_config.gd:9, world/poi_config.gd:12, world/poi_config.gd:13, world/poi_config.gd:22)
  - Ensure gridmap scene paths pass `ResourceLoader.exists` to avoid pre-sampling filtering. (world/poi_spawner.gd:12, world/poi_spawner.gd:14, world/poi_spawner.gd:168)
- When adjusting chunk geometry:
  - Recheck terrain/road resolution, road width, and tilt cap to avoid drivability regressions. (world/chunk_generator.gd:5, world/chunk_generator.gd:6, world/chunk_generator.gd:278, world/chunk_generator.gd:279)
  - Keep chunk nav-strip and enemy-agent dimensions coherent (`NavigationMesh.agent_radius/height`, strip width from `ROAD_WIDTH`, zombie `NavigationAgent3D` radius/height). (world/chunk_generator.gd:335, world/chunk_generator.gd:337, world/chunk_generator.gd:338, world/chunk_generator.gd:342, enemies/zombie.tscn:51, enemies/zombie.tscn:52)
- When adjusting streaming strategy:
  - Verify `CHUNKS_AHEAD/BEHIND` and `_process` threshold logic stay aligned to avoid holes or over-allocation. (world/world_generator.gd:4, world/world_generator.gd:5, world/world_generator.gd:54, world/world_generator.gd:61)
- When changing procedural building logic:
  - Preserve valid room scan + BFS expansion behavior in `BuildingGenerator`. (world/building/building_generator.gd:25, world/building/building_generator.gd:33, world/building/building_generator.gd:100)

## Source Files Used
- world/world_generator.gd
- world/chunk_generator.gd
- world/poi_spawner.gd
- world/poi_config.gd
- world/building/building_generator.gd
- enemies/monster.gd
- enemies/zombie.tscn
- tests/test_monster_navigation.gd
- project.godot

## Completeness notes
- This document covers partition boundaries, control flow, data contracts, failure modes, and change-check items.
- Unknown: CPU/memory cost and real POI scene asset completeness cannot be quantified from the evidence set alone and require runtime profiling plus asset audit.