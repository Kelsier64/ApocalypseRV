# World Generation and POI Pipeline

## Scope
This document describes the runtime pipeline that starts from the project main scene and produces streamed world chunks, roads, navigation, points of interest (POIs), ambient zombies, and POI-specific loot/enemies.

Related contract docs:
- [World Generation Module](../modules/world-generation.md)
- [World Generation POI System Module](../modules/world-generation-poi-system.md)
- [Procedural Building Design](world-generation-procedural-buildings.md)

## Runtime Entry and Scene Wiring
The project main scene is `res://world/test_world.tscn`, and that scene includes a `WorldGenerator` node with `world/world_generator.gd` attached.

Evidence:
- `project.godot:16`
- `world/test_world.tscn:43`
- `world/test_world.tscn:44`

## End-to-End Pipeline
1. `WorldGenerator._ready()` initializes shared noise generators, creates one `POISpawner`, generates behind chunks, and then generates current plus ahead chunks.
2. Each chunk is a new `Node3D` with `world/chunk_generator.gd` assigned as script, and `generate_chunk` is called with shared noise/spawner state.
3. `ChunkGenerator.generate_chunk` builds terrain mesh, road mesh, and navigation region, then optionally places a POI and always attempts ambient road zombie spawning.
4. If a POI was accepted, chunk generation delegates to `POISpawner` for building instancing, loot spawn, and enemy spawn.
5. At runtime, `WorldGenerator._process()` streams by player Z: spawn ahead when buffer is low, and despawn oldest chunks that are too far behind.

Evidence:
- `world/world_generator.gd:17`
- `world/world_generator.gd:23`
- `world/world_generator.gd:41`
- `world/world_generator.gd:66`
- `world/world_generator.gd:72`
- `world/chunk_generator.gd:33`
- `world/chunk_generator.gd:54`
- `world/chunk_generator.gd:55`
- `world/chunk_generator.gd:56`
- `world/chunk_generator.gd:66`
- `world/chunk_generator.gd:67`
- `world/chunk_generator.gd:68`
- `world/chunk_generator.gd:69`
- `world/chunk_generator.gd:71`
- `world/world_generator.gd:54`
- `world/world_generator.gd:61`
- `world/world_generator.gd:62`

## Chunk Streaming Behavior
### Initial world fill
`CHUNKS_BEHIND = 2` and `CHUNKS_AHEAD = 3`. Startup creates behind chunks first, then one current plus ahead chunks (`CHUNKS_AHEAD + 1`).

Evidence:
- `world/world_generator.gd:4`
- `world/world_generator.gd:5`
- `world/world_generator.gd:23`
- `world/world_generator.gd:41`

### Streaming trigger math
The ahead-spawn threshold and behind-despawn threshold are both tied to fixed chunk length (`150.0`) and player global Z.

Evidence:
- `world/world_generator.gd:20`
- `world/world_generator.gd:48`
- `world/world_generator.gd:54`
- `world/world_generator.gd:61`

### Turn continuity
Each chunk returns the next transform, and `next_turn_angle` is randomized in `[-0.25, 0.25]` for gradual snake-like roads.

Evidence:
- `world/world_generator.gd:72`
- `world/world_generator.gd:84`
- `world/world_generator.gd:88`

## Terrain, Road, and Navigation Construction
### Terrain
Terrain uses a coarse noise layer plus detail noise and produces an 80x80 triangulated grid over a 150m chunk footprint.

Evidence:
- `world/chunk_generator.gd:4`
- `world/chunk_generator.gd:5`
- `world/chunk_generator.gd:24`
- `world/chunk_generator.gd:25`
- `world/chunk_generator.gd:141`
- `world/chunk_generator.gd:142`

### Road
Road width is 15m, generated from a cubic Bezier centerline and blended against terrain with tilt limiting.

Evidence:
- `world/chunk_generator.gd:6`
- `world/chunk_generator.gd:111`
- `world/chunk_generator.gd:254`
- `world/chunk_generator.gd:280`

### Navigation
Each chunk creates a `NavigationMesh` and `NavigationRegion3D` aligned to the road strip, with explicit agent dimensions.

Evidence:
- `world/chunk_generator.gd:334`
- `world/chunk_generator.gd:336`
- `world/chunk_generator.gd:337`
- `world/chunk_generator.gd:338`
- `world/chunk_generator.gd:377`

## POI Selection and Placement in Chunk Space
### Placement gate
A chunk attempts POI placement with 50% probability, then rejects a chosen POI if it is too close to road centerline relative to `min_road_distance`.

Evidence:
- `world/chunk_generator.gd:50`
- `world/chunk_generator.gd:76`
- `world/chunk_generator.gd:88`
- `world/chunk_generator.gd:89`
- `world/chunk_generator.gd:91`

### Footprint flattening and blend
Accepted POIs define local flattening controls (`footprint_radius`, `footprint_blend`) that suppress micro detail and blend heights around the POI footprint.

Evidence:
- `world/chunk_generator.gd:96`
- `world/chunk_generator.gd:97`
- `world/chunk_generator.gd:163`
- `world/chunk_generator.gd:165`
- `world/chunk_generator.gd:168`
- `world/chunk_generator.gd:176`

## POI Scene Availability Mismatch Risk
## Why this is risky
The POI config references six gridmap scene paths (`gas_station`, `motel`, `rest_stop`, `apartment`, `warehouse`, `bunker`), while the current scene directory also contains `convenience_store` and `gas_station+store` assets. `POISpawner.pick_poi()` filters out gridmap entries when scene files are missing and warns once per missing path. This means content availability directly changes weighted rollout and can silently skew POI distribution.

Configured gridmap references:
- `res://world/building/scenes/gas_station.tscn`
- `res://world/building/scenes/motel.tscn`
- `res://world/building/scenes/rest_stop.tscn`
- `res://world/building/scenes/apartment.tscn`
- `res://world/building/scenes/warehouse.tscn`
- `res://world/building/scenes/bunker.tscn`

Observed scene assets currently in `world/building/scenes`:
- `convenience_store.tscn`
- `gas_station+store.tscn`
- `gas_station.tscn`
- `motel.tscn`

Evidence:
- `world/poi_config.gd:7`
- `world/poi_config.gd:30`
- `world/poi_config.gd:53`
- `world/poi_config.gd:75`
- `world/poi_config.gd:97`
- `world/poi_config.gd:120`
- `world/poi_spawner.gd:11`
- `world/poi_spawner.gd:14`
- `world/poi_spawner.gd:163`
- `world/poi_spawner.gd:170`
- `world/poi_spawner.gd:178`
- `world/building/scenes/convenience_store.tscn:1`
- `world/building/scenes/gas_station+store.tscn:1`
- `world/building/scenes/gas_station.tscn:1`
- `world/building/scenes/motel.tscn:1`

## Operational Notes and Unknowns
- `WorldGenerator._process()` exits early if `player` is unset. In `test_world.tscn`, `WorldGenerator` has script assignment shown, but no explicit `player` property assignment is visible in the inspected lines. Confirm whether editor wiring or runtime injection sets this export in actual gameplay scenes.
- Noise seeds are hardcoded (`1337` and `7331`), so world profile is deterministic for a fixed random sequence but not exposed in scene/config as a tunable setting.

Evidence:
- `world/world_generator.gd:14`
- `world/world_generator.gd:45`
- `world/test_world.tscn:43`
- `world/test_world.tscn:44`
- `world/world_generator.gd:94`
- `world/world_generator.gd:103`
