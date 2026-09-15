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

## Configured POI Content
The active pool contains `gas_station`, `motel`, and `procedural_tower`. Missing `rest_stop`, `apartment`, `warehouse`, and `bunker` entries were removed; reintroduce them only when their scene assets exist. This preserves the previously effective pool and weights.

`tests/test_poi_resources.gd` checks every configured building, loot, and enemy scene. Additional assets such as `convenience_store.tscn` and `gas_station+store.tscn` remain available but are not automatically added to the pool.
