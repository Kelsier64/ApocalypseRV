# World Generation POI System Contract

## Module Surface
- Config table: `world/poi_config.gd` (`POIConfig.POI_TABLE`)
- Runtime spawner: `world/poi_spawner.gd` (`POISpawner`)
- Chunk caller: `world/chunk_generator.gd`

Evidence:
- `world/poi_config.gd:2`
- `world/poi_config.gd:4`
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
- `world/poi_config.gd:6`
- `world/poi_config.gd:8`
- `world/poi_config.gd:9`
- `world/poi_config.gd:10`
- `world/poi_config.gd:11`
- `world/poi_config.gd:12`
- `world/poi_config.gd:13`
- `world/poi_config.gd:22`
- `world/poi_config.gd:145`
- `world/poi_config.gd:150`
- `world/poi_config.gd:151`
- `world/poi_config.gd:152`

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

## POI Scene Availability Mismatch Risk
Configured gridmap POIs are:
- `gas_station`
- `motel`
- `rest_stop`
- `apartment`
- `warehouse`
- `bunker`

Current scene assets in `world/building/scenes` include:
- `convenience_store.tscn`
- `gas_station+store.tscn`
- `gas_station.tscn`
- `motel.tscn`

Concrete risk:
- Asset/config drift can make weighted pools diverge from design intent because unavailable gridmap entries are filtered out at selection time.
- Additional scene assets that are not referenced by `POI_TABLE` do not enter the random pool.

Evidence:
- `world/poi_config.gd:6`
- `world/poi_config.gd:29`
- `world/poi_config.gd:52`
- `world/poi_config.gd:74`
- `world/poi_config.gd:96`
- `world/poi_config.gd:119`
- `world/poi_spawner.gd:11`
- `world/poi_spawner.gd:14`
- `world/building/scenes/convenience_store.tscn:1`
- `world/building/scenes/gas_station+store.tscn:1`
- `world/building/scenes/gas_station.tscn:1`
- `world/building/scenes/motel.tscn:1`

## Related Design Docs
- [World Generation and POIs](../design/world-generation-and-pois.md)
- [Procedural Building Design](../design/world-generation-procedural-buildings.md)

## Unknowns
- This module exposes no explicit telemetry for effective post-filter POI weights, so runtime distribution changes due to missing assets must be inferred from warnings or behavior.

Evidence:
- `world/poi_spawner.gd:178`
