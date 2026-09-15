# World Generation Module Contract

## Module
- Script: `world/world_generator.gd`
- Runtime host: `WorldGenerator` node in `world/test_world.tscn`

Evidence:
- `world/world_generator.gd:1`
- `world/test_world.tscn:43`
- `world/test_world.tscn:44`

## Responsibilities
The module owns chunk streaming lifecycle, shared terrain/detail noise initialization, and transfer of shared generation dependencies into chunk instances.

Evidence:
- `world/world_generator.gd:17`
- `world/world_generator.gd:66`
- `world/world_generator.gd:72`
- `world/world_generator.gd:92`

## Public Configuration Contract
- `player: Node3D` is exported and required for runtime streaming decisions in `_process()`.
- `CHUNKS_AHEAD` and `CHUNKS_BEHIND` define streaming window.

Evidence:
- `world/world_generator.gd:14`
- `world/world_generator.gd:45`
- `world/world_generator.gd:48`
- `world/world_generator.gd:4`
- `world/world_generator.gd:5`

## Chunk Script Contract
Each spawned chunk is created as `Node3D` with `world/chunk_generator.gd` assigned as script, and must expose:
`generate_chunk(start_transform, next_turn_angle, shared_noise, shared_detail_noise, shared_poi_spawner) -> Transform3D`.

Evidence:
- `world/world_generator.gd:3`
- `world/world_generator.gd:67`
- `world/world_generator.gd:72`
- `world/chunk_generator.gd:33`

## State Contract
`active_chunks` entries are dictionaries with `node`, `start_z`, and `end_z`. Streaming decisions depend on this shape.

Evidence:
- `world/world_generator.gd:7`
- `world/world_generator.gd:31`
- `world/world_generator.gd:53`
- `world/world_generator.gd:59`

## Noise Contract
World generation uses two shared `FastNoiseLite` instances with fixed seeds and tuned fractal settings:
- terrain noise: seed 1337, very low frequency
- detail noise: seed 7331, higher frequency

Evidence:
- `world/world_generator.gd:10`
- `world/world_generator.gd:11`
- `world/world_generator.gd:94`
- `world/world_generator.gd:96`
- `world/world_generator.gd:103`
- `world/world_generator.gd:105`

## Failure and Guard Behavior
- If `player` is null, `_process()` returns immediately and no streaming updates occur.
- Old chunks are despawned with `queue_free()` only after crossing behind-threshold criteria.

Evidence:
- `world/world_generator.gd:45`
- `world/world_generator.gd:62`

## Related Design Docs
- [World Generation and POIs](../design/world-generation-and-pois.md)
- [Procedural Building Design](../design/world-generation-procedural-buildings.md)

## Unknowns
- The module does not enforce assignment of `player` internally; scene/editor wiring is assumed.
- No adaptive chunk size parameter was found; `150.0` appears as a fixed length used in startup and stream checks.

Evidence:
- `world/world_generator.gd:20`
- `world/world_generator.gd:54`
- `world/world_generator.gd:61`
