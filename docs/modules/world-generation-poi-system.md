# World Generation POI System Contract

## Module Surface
- Config table: `world/poi_config.gd` (`POIConfig.POI_TABLE`)
- Runtime spawner: `world/poi_spawner.gd` (`POISpawner`)
- Chunk caller: `world/chunk_generator.gd`

Evidence:
- `world/poi_config.gd`
- `world/poi_config.gd`
- `world/poi_spawner.gd:2`
- `world/poi_spawner.gd:8`
- `world/chunk_generator.gd:67`
- `world/chunk_generator.gd:68`
- `world/chunk_generator.gd:69`

## POI Entry Contract
Each POI entry is a dictionary with weighted selection plus gameplay payload. In current data, entries include:
- `id`, `type`, `weight`
- terrain placement controls: `footprint_radius`, `footprint_blend`, `min_road_distance`
- content controls: `loot`, `enemies`
- for procedural POIs: `procedural_config` with min/max room count

Evidence:
- `world/poi_config.gd`
- `world/poi_config.gd`
- `world/poi_config.gd`
- `world/poi_config.gd`
- `world/poi_config.gd`
- `world/poi_config.gd`
- `world/poi_config.gd`
- `world/poi_config.gd`
- `world/poi_config.gd`
- `world/poi_config.gd`
- `world/poi_config.gd`
- `world/poi_config.gd`

## Selection Contract
`pick_poi()` performs weighted random selection from config entries, but gridmap entries are included only when scene assets exist.

Evidence:
- `world/poi_spawner.gd:8`
- `world/poi_spawner.gd:11`
- `world/poi_spawner.gd:12`
- `world/poi_spawner.gd:14`
- `world/poi_spawner.gd:24`

## Spawn Contract
### Building
- `spawn_building` instantiates either gridmap scene content or procedural building node.

Evidence:
- `world/poi_spawner.gd:31`
- `world/poi_spawner.gd:37`
- `world/poi_spawner.gd:38`
- `world/poi_spawner.gd:40`

### Loot
- `spawn_loot` uses configured count/radius/table.
- If building markers are found (`LootSpawns` or `LootSpawn*` markers), loot uses marker transforms; otherwise random radius placement around center.

Evidence:
- `world/poi_spawner.gd:49`
- `world/poi_spawner.gd:53`
- `world/poi_spawner.gd:54`
- `world/poi_spawner.gd:55`
- `world/poi_spawner.gd:60`
- `world/poi_spawner.gd:67`
- `world/poi_spawner.gd:71`
- `world/poi_spawner.gd:181`
- `world/poi_spawner.gd:186`
- `world/poi_spawner.gd:193`

### Enemies
- `spawn_enemies` uses configured count/radius and a scene path (default zombie), and resolves height through a callback from chunk generator.

Evidence:
- `world/poi_spawner.gd:84`
- `world/poi_spawner.gd:89`
- `world/poi_spawner.gd:90`
- `world/poi_spawner.gd:91`
- `world/chunk_generator.gd:69`
- `world/chunk_generator.gd:101`

## Scene Availability Guard Contract
`POISpawner` caches loaded scenes and validates file existence before load. Missing paths trigger warning emission once per path.

Evidence:
- `world/poi_spawner.gd:4`
- `world/poi_spawner.gd:5`
- `world/poi_spawner.gd:145`
- `world/poi_spawner.gd:153`
- `world/poi_spawner.gd:163`
- `world/poi_spawner.gd:174`
- `world/poi_spawner.gd:178`

## Configured POI Content
The active pool contains `gas_station`, `motel`, and `procedural_tower`. Missing `rest_stop`, `apartment`, `warehouse`, and `bunker` entries were removed; reintroduce them only when their scene assets exist. This preserves the previously effective pool and weights.

`tests/test_poi_resources.gd` checks every configured building, loot, and enemy scene. Additional assets such as `convenience_store.tscn` and `gas_station+store.tscn` remain available but are not automatically added to the pool.
## Related Design Docs
- [World Generation and POIs](../design/world-generation-and-pois.md)
- [Procedural Building Design](../design/world-generation-procedural-buildings.md)

## Unknowns
- This module exposes no explicit telemetry for effective post-filter POI weights, so runtime distribution changes due to missing assets must be inferred from warnings or behavior.

Evidence:
- `world/poi_spawner.gd:178`
