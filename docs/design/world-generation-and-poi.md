# World Generation and POI

## Why
This partition directly supports the runtime loop where the world keeps streaming ahead, old chunks are reclaimed, and POI content is spawned from data/config at chunk generation time. If this pipeline becomes unstable, progression through the road corridor and scavenging opportunities both degrade. (world/world_generator.gd:54, world/world_generator.gd:61, world/chunk_generator.gd:66, world/chunk_generator.gd:71, world/poi_config.gd:4, world/poi_spawner.gd:8)

## Problem
The world is assembled dynamically at runtime through chunk chaining rather than being fully baked once, and must solve all of the following at the same time:
- Keep drivable road ahead of the player while releasing stale chunks behind to prevent unbounded scene growth. (world/world_generator.gd:4, world/world_generator.gd:5, world/world_generator.gd:54, world/world_generator.gd:61, world/world_generator.gd:62)
- Generate terrain, road, and optional POI content inside each chunk while preserving drivability. (world/chunk_generator.gd:33, world/chunk_generator.gd:54, world/chunk_generator.gd:55, world/chunk_generator.gd:278, world/chunk_generator.gd:282)
- Generate chunk-local navigation surfaces aligned to the road so enemy agents can request valid path targets across streamed chunks. (world/chunk_generator.gd:56, world/chunk_generator.gd:334, world/chunk_generator.gd:335, world/chunk_generator.gd:377, enemies/monster.gd:341, enemies/monster.gd:353)
- Support weighted POI selection from config, tolerate missing resources, and support both gridmap and procedural building sources. (world/poi_spawner.gd:8, world/poi_spawner.gd:12, world/poi_spawner.gd:14, world/poi_spawner.gd:31, world/poi_spawner.gd:37, world/poi_spawner.gd:120)

## Goals
- Maintain continuous world streaming: create behind and ahead buffers at initialization, then dynamically add/remove chunks based on player z position. (world/world_generator.gd:23, world/world_generator.gd:41, world/world_generator.gd:44, world/world_generator.gd:54, world/world_generator.gd:61)
- Drive both terrain blending and road mesh generation from one road curve for visual/collision consistency. (world/chunk_generator.gd:107, world/chunk_generator.gd:154, world/chunk_generator.gd:254, world/chunk_generator.gd:237, world/chunk_generator.gd:320)
- Keep road-aligned navigation data in lockstep with chunk generation so zombie patrol/chase steering can consume map data when available and degrade safely when not. (world/chunk_generator.gd:56, world/chunk_generator.gd:334, world/chunk_generator.gd:341, world/chunk_generator.gd:365, enemies/monster.gd:185, enemies/monster.gd:207, enemies/monster.gd:285, enemies/monster.gd:314, enemies/monster.gd:318)
- Keep monster movement resilient around blockers: chase intent uses navigation-first steering with direct fallback, and prolonged low-progress movement triggers bounded anti-stuck recovery. (enemies/monster.gd:207, enemies/monster.gd:285, enemies/monster.gd:314, enemies/monster.gd:334, enemies/monster.gd:350, enemies/monster.gd:355)
- Keep POI data-driven (weight, footprint, min_road_distance, loot, enemies) and spawn buildings/drops/enemies inside chunk runtime flow. (world/poi_config.gd:4, world/poi_config.gd:9, world/poi_config.gd:10, world/poi_config.gd:12, world/poi_config.gd:13, world/chunk_generator.gd:66, world/chunk_generator.gd:67, world/chunk_generator.gd:68)
- Keep a clear entry scene path: main scene points directly to world test scene for faster world-pipeline iteration. (project.godot:16)

## Tradeoffs
- Determinism vs variation: noise seeds are fixed (terrain profiles are more reproducible), but chunk turns and POI appearance use random sampling, so runs are not fully deterministic. (world/world_generator.gd:94, world/world_generator.gd:103, world/world_generator.gd:88, world/chunk_generator.gd:50)
- Generation quality vs cost: terrain resolution is 80 and uses concave collision, improving surface detail while increasing per-chunk mesh/collision generation cost. (world/chunk_generator.gd:5, world/chunk_generator.gd:135, world/chunk_generator.gd:237, world/chunk_generator.gd:320)
- Content flexibility vs failure visibility: POISpawner skips missing scenes and warns to avoid hard crashes, but this can reduce actual POI variety. (world/poi_spawner.gd:14, world/poi_spawner.gd:19, world/poi_spawner.gd:168, world/poi_spawner.gd:178)

## Workflow
1. Startup loads the world test scene and WorldGenerator initializes noise + POISpawner. (project.godot:16, world/world_generator.gd:17, world/world_generator.gd:18)
2. Startup pre-fills behind chunks, then creates current + ahead chunk buffers. (world/world_generator.gd:23, world/world_generator.gd:24, world/world_generator.gd:41, world/world_generator.gd:42)
3. Each chunk defines road by Bezier curve, builds terrain/road meshes, and calls `_build_navigation_region()` to attach a road-following `NavigationRegion3D` strip. (world/chunk_generator.gd:43, world/chunk_generator.gd:44, world/chunk_generator.gd:54, world/chunk_generator.gd:55, world/chunk_generator.gd:56, world/chunk_generator.gd:334, world/chunk_generator.gd:377)
4. POI placement is attempted with roughly 50% probability; if too close to road it is skipped, otherwise building/loot/enemies are spawned in that chunk, then ambient road zombies are spawned. (world/chunk_generator.gd:50, world/chunk_generator.gd:88, world/chunk_generator.gd:90, world/chunk_generator.gd:66, world/chunk_generator.gd:67, world/chunk_generator.gd:68, world/chunk_generator.gd:71, world/chunk_generator.gd:385)
5. Zombie AI patrol/chase uses `_get_navigation_direction()` and consumes `NavigationAgent3D` path data when `_can_use_navigation()` confirms a valid map iteration; otherwise movement falls back to direct steering. (enemies/monster.gd:185, enemies/monster.gd:207, enemies/monster.gd:285, enemies/monster.gd:314, enemies/monster.gd:318, enemies/monster.gd:323)
6. The main loop continues pushing chunks forward and reclaiming old chunks based on player position. (world/world_generator.gd:48, world/world_generator.gd:54, world/world_generator.gd:55, world/world_generator.gd:61, world/world_generator.gd:62)

## Interfaces
- `WorldGenerator.generate control`
  - `_spawn_next_chunk()`: creates `Node3D`, attaches `chunk_generator.gd`, calls `generate_chunk(start_transform, next_turn_angle, shared_noise, shared_detail_noise, shared_poi_spawner)`, and updates `next_transform` + `next_turn_angle`. (world/world_generator.gd:66, world/world_generator.gd:68, world/world_generator.gd:72, world/world_generator.gd:86, world/world_generator.gd:88)
- `ChunkGenerator`
  - `generate_chunk(start_transform, next_turn_angle, shared_noise, shared_detail_noise, shared_poi_spawner) -> Transform3D`: generates the current chunk, builds chunk navigation strip, and returns the next chunk start transform. (world/chunk_generator.gd:33, world/chunk_generator.gd:56, world/chunk_generator.gd:57, world/chunk_generator.gd:334, world/chunk_generator.gd:377)
  - `_build_navigation_region() -> void`: creates a `NavigationMesh` strip along the road (`nav_segments = 44`) and mounts it into `ChunkNavigationRegion`. (world/chunk_generator.gd:334, world/chunk_generator.gd:341, world/chunk_generator.gd:374, world/chunk_generator.gd:375, world/chunk_generator.gd:378)
- `Monster` navigation consumer
  - `NavigationAgent3D` child is expected by scene composition and resolved in `_ready`, where desired distances are synchronized with exported tuning values. (enemies/zombie.tscn:48, enemies/monster.gd:15, enemies/monster.gd:16, enemies/monster.gd:81, enemies/monster.gd:83, enemies/monster.gd:84)
  - `_can_use_navigation() / _get_navigation_direction(destination)` form the steering contract used by both patrol and chase paths. (enemies/monster.gd:185, enemies/monster.gd:207, enemies/monster.gd:285, enemies/monster.gd:314)
  - `_update_stuck_watchdog(delta, moving_intent)` and `_trigger_stuck_recovery()` provide bounded unstuck recovery through progress thresholds, cooldown, and short fallback steering windows. (enemies/monster.gd:25, enemies/monster.gd:26, enemies/monster.gd:27, enemies/monster.gd:28, enemies/monster.gd:334, enemies/monster.gd:350, enemies/monster.gd:355)
- `POISpawner`
  - `pick_poi() -> Dictionary`: weighted sampling after filtering valid entries. (world/poi_spawner.gd:8, world/poi_spawner.gd:14, world/poi_spawner.gd:22)
  - `spawn_building/spawn_loot/spawn_enemies`: generates content from POI config. (world/poi_spawner.gd:31, world/poi_spawner.gd:49, world/poi_spawner.gd:84)
- `POIConfig`
  - `POI_TABLE`: primary world-content config source (type, weight, loot, enemies, procedural_config). (world/poi_config.gd:4, world/poi_config.gd:145, world/poi_config.gd:146, world/poi_config.gd:13, world/poi_config.gd:22, world/poi_config.gd:150)

## Edge cases
- No player reference: `_process` returns immediately, so streaming updates do not run. (world/world_generator.gd:45)
- Navigation strip skip path: if nav vertex buffer is too small, `_build_navigation_region()` exits early and no chunk region is attached. (world/chunk_generator.gd:365, world/chunk_generator.gd:366)
- Zombie steering fallback path: if `NavigationAgent3D` is missing, invalid, or lacks a ready map iteration, monster movement falls back to direct vector steering. (enemies/monster.gd:276, enemies/monster.gd:285, enemies/monster.gd:289, enemies/monster.gd:314, enemies/monster.gd:318)
- Stuck recovery trigger path: when move intent is active but frame-to-frame progress remains below threshold for too long, recovery forces repath and starts cooldown. (enemies/monster.gd:334, enemies/monster.gd:347, enemies/monster.gd:350, enemies/monster.gd:355)
- Empty POI pool or total weight <= 0: `pick_poi` returns an empty dictionary and no POI is generated. (world/poi_spawner.gd:19)
- Missing gridmap POI scenes: entries are filtered before sampling and warnings are emitted without repetition. (world/poi_spawner.gd:12, world/poi_spawner.gd:14, world/poi_spawner.gd:163, world/poi_spawner.gd:178)
- POI too close to road: `_try_place_poi` rejects placement to keep roads drivable. (world/chunk_generator.gd:87, world/chunk_generator.gd:88, world/chunk_generator.gd:90)
- Excessive road tilt: height difference is clamped to 10 degrees to reduce undrivable surfaces. (world/chunk_generator.gd:278, world/chunk_generator.gd:279, world/chunk_generator.gd:282)

## Validation
- Automated verification in evidence set:
  - `tests/test_monster_navigation.gd` targets the monster navigation/climb helper contract surface used by this partition (navigation gating, chase direction resolution, fallback steering behavior, and stuck/elevation helper methods), but current helper API drift should be reconciled before treating this script as a green gate. (tests/test_monster_navigation.gd:6, tests/test_monster_navigation.gd:8, tests/test_monster_navigation.gd:11, tests/test_monster_navigation.gd:37, tests/test_monster_navigation.gd:40, enemies/monster.gd:1120)
- Manual verification flow:
  - Enter the world from the main scene and confirm chunks keep generating forward while old chunks are reclaimed behind. (project.godot:16, world/world_generator.gd:54, world/world_generator.gd:61)
  - Confirm chunk content includes terrain/road mesh plus collision. (world/chunk_generator.gd:135, world/chunk_generator.gd:251, world/chunk_generator.gd:237, world/chunk_generator.gd:320)
  - Confirm each spawned chunk contributes a `ChunkNavigationRegion` with polygons derived from the road strip. (world/chunk_generator.gd:56, world/chunk_generator.gd:334, world/chunk_generator.gd:368, world/chunk_generator.gd:374, world/chunk_generator.gd:375, world/chunk_generator.gd:377, world/chunk_generator.gd:380)
  - Confirm zombie scene contains `NavigationAgent3D`, then observe patrol/chase pathing around curved roads; optionally disable agent to verify direct-steering fallback still moves the monster. (enemies/zombie.tscn:48, enemies/monster.gd:185, enemies/monster.gd:207, enemies/monster.gd:285, enemies/monster.gd:314, enemies/monster.gd:318)
  - Confirm anti-stuck runtime: place a monster in a wall/corner trap scenario and verify low-progress accumulation triggers `_trigger_stuck_recovery`, then confirm recovery cooldown prevents continuous thrashing. (enemies/monster.gd:334, enemies/monster.gd:350, enemies/monster.gd:355, enemies/monster.gd:357)
  - Validate POI pipeline: sampling -> building -> loot -> enemies, and verify missing-scene warning behavior. (world/poi_spawner.gd:8, world/poi_spawner.gd:31, world/poi_spawner.gd:49, world/poi_spawner.gd:84, world/poi_spawner.gd:178)
- Runtime chunk/POI generation behavior still requires manual validation in-scene; the automated test coverage in this evidence set is currently focused on monster navigation contract behavior.

## Related modules
- `world/building/building_generator.gd`: procedural POI building generator loaded by POISpawner and configured via `max_rooms`. (world/poi_spawner.gd:121, world/poi_spawner.gd:128, world/building/building_generator.gd:2)
- `world/building/scenes/*.tscn`: source scene paths for gridmap POIs. (world/poi_config.gd:7, world/poi_config.gd:30, world/poi_config.gd:53)
- `enemies/zombie.tscn`: used both for POI enemies and random road zombies, and now embeds `NavigationAgent3D` consumed by `Monster`. (world/poi_config.gd:25, world/chunk_generator.gd:385, enemies/zombie.tscn:48, enemies/monster.gd:78)
- `enemies/monster.gd`: patrol/chase steering helper methods consume chunk navigation maps when available. (enemies/monster.gd:185, enemies/monster.gd:207, enemies/monster.gd:285, enemies/monster.gd:314)
- `props/*.tscn`: source scenes used by loot tables. (world/poi_config.gd:17, world/poi_config.gd:18, world/poi_config.gd:19)

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
- This refreshed version covers the main world/POI generation path, core data contracts, and primary failure paths for the current evidence set.
- Unknown: the current evidence set does not include runtime profiling or real asset-completeness audit output, so no quantitative upper-bound performance or missing-asset ratio conclusion is provided.