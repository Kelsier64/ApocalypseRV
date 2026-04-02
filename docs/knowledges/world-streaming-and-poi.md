# Knowledge: World Streaming and POI Generation

## 1. Why This Matters
- The world is generated incrementally during runtime; chunk and POI logic controls core gameplay pacing.
- Performance and reliability issues in these systems have immediate impact on playability.
- Content correctness depends on alignment between POI config data and scene assets.

## 2. Trigger Conditions
- Editing `world/world_generator.gd` streaming boundaries or tracked-node logic.
- Changing chunk size/resolution/road parameters in `world/chunk_generator.gd`.
- Adding/removing POI entries or loot/enemy tables in `world/poi_config.gd`.
- Updating procedural building generation in `world/building/building_generator.gd`.

## 3. Canonical Workflow
1. `WorldGenerator` initializes noise and POI spawner.
2. Initial chunks are created behind/current/ahead, then updated continuously by `_process` checks.
3. Each chunk creates Bezier road + terrain mesh/collision, optionally places one POI candidate.
4. If POI passes distance constraints, spawner creates building/loot/enemies.
5. Procedural POI type instantiates `BuildingGenerator`, which does elevator-rooted BFS room expansion.

## 4. Commands/APIs/Procedures
- Runtime command:
  - `godot --path . res://world/test_world.tscn`
- Main APIs:
  - `WorldGenerator._spawn_next_chunk()`
- `ChunkGenerator.generate_chunk(start_transform, next_turn_angle, shared_noise, shared_detail_noise, shared_poi_spawner)`
  - `POISpawner.pick_poi()`, `spawn_building`, `spawn_loot`, `spawn_enemies`
  - `spawn_loot` first consumes building `LootSpawns` marker points (`Marker3D`) and only falls back to radius random positions if markers are unavailable.
  - `BuildingGenerator.generate()`
- Content generation utility:
  - `godot --headless -s generate_store.gd` generates `world/building/scenes/convenience_store.tscn`.

## 5. Edge Cases and Failure Patterns
- POI scenes referenced in config but missing in filesystem create warnings and partial POI outcomes.
- Streaming boundaries use Z heuristics while roads can curve; edge cases can produce less intuitive chunk timing.
- Runtime-generated concave collision meshes can produce frame spikes at high spawn cadence.
- Building door sealing can mismatch intended open/closed state on some generated layouts.

## 6. Validation Checklist
- [ ] Drive continuously and observe stable chunk spawn/despawn without runaway growth.
- [ ] Confirm each configured POI either loads valid scene or is intentionally handled.
- [ ] Verify enemies spawn above terrain and engage player.
- [ ] Verify loot appears around POI and is collectible/scrappable.
- [ ] Inspect several procedural towers for severe overlap/sealing issues.

## 7. Related Modules
- `docs/module/world-generation.md`
- `docs/module/procedural-building.md`

## 8. Source Files Used
- `world/world_generator.gd`
- `world/chunk_generator.gd`
- `world/poi_config.gd`
- `world/poi_spawner.gd`
- `world/building/building_generator.gd`
- `world/building/room_node.gd`
- `world/building/elevator_platform.gd`
- `generate_store.gd`

## 9. Completeness Notes
- This doc covers generation behavior currently implemented in source.
- It does not include future weather/day-night systems described conceptually in `GDD.md` but not present in generation scripts.
