# World Generation Procedural Building Module Contract

## Module Surface
- Generator script: `world/building/building_generator.gd` (`BuildingGenerator`)
- Room metadata script: `world/building/room_node.gd` (`RoomNode`)
- Elevator movement script: `world/building/elevator_platform.gd`

Evidence:
- `world/building/building_generator.gd:2`
- `world/building/room_node.gd:2`
- `world/building/elevator_platform.gd:1`

## Configuration Contract
`BuildingGenerator` exports:
- `max_rooms: int` default 20
- `seed_value: int` default -1 (random unless non-negative)

`RoomNode` exports:
- `room_name`
- `weight`
- `grid_size`
- `doors`

Evidence:
- `world/building/building_generator.gd:6`
- `world/building/building_generator.gd:7`
- `world/building/room_node.gd:4`
- `world/building/room_node.gd:5`
- `world/building/room_node.gd:6`
- `world/building/room_node.gd:9`

## Generation Contract
On `_ready()`, generator loads room defs, optionally seeds RNG, and calls `generate()`.

Evidence:
- `world/building/building_generator.gd:17`
- `world/building/building_generator.gd:18`
- `world/building/building_generator.gd:20`
- `world/building/building_generator.gd:23`

`generate()` guarantees:
- Occupancy reset before placement.
- Elevator reserved and instantiated first.
- Expansion through compatible doors until frontier exhausted or room cap reached.
- Unresolved doors sealed with CSG blockers.

Evidence:
- `world/building/building_generator.gd:67`
- `world/building/building_generator.gd:73`
- `world/building/building_generator.gd:75`
- `world/building/building_generator.gd:100`
- `world/building/building_generator.gd:139`
- `world/building/building_generator.gd:172`
- `world/building/building_generator.gd:181`

## Geometric Contract
- World scale is `BASE_UNIT = 9.0` meters per grid cell.
- Room/world placement multiplies logical grid origin by `BASE_UNIT`.
- `RoomNode.get_real_size()` converts `grid_size` to world units by `* 9.0`.

Evidence:
- `world/building/building_generator.gd:4`
- `world/building/building_generator.gd:79`
- `world/building/building_generator.gd:146`
- `world/building/room_node.gd:12`

## Door Compatibility Contract
- Door data uses wall labels and grid offsets.
- Neighbor target and opposite wall matching are centralized in helper methods.

Evidence:
- `world/building/building_generator.gd:14`
- `world/building/building_generator.gd:104`
- `world/building/building_generator.gd:112`
- `world/building/building_generator.gd:208`
- `world/building/building_generator.gd:216`

## Elevator Platform Contract
`elevator_platform.gd` moves between `bottom_y` and `top_y` at `speed`, waits at limits, then flips direction. Movement is updated in `_physics_process`.

Evidence:
- `world/building/elevator_platform.gd:6`
- `world/building/elevator_platform.gd:7`
- `world/building/elevator_platform.gd:8`
- `world/building/elevator_platform.gd:9`
- `world/building/elevator_platform.gd:15`
- `world/building/elevator_platform.gd:20`

## Integration Contract With POI System
`POISpawner._create_procedural` creates this module dynamically and sets `max_rooms` from POI config range.

Evidence:
- `world/poi_spawner.gd:120`
- `world/poi_spawner.gd:123`
- `world/poi_spawner.gd:128`
- `world/poi_config.gd:150`
- `world/poi_config.gd:151`
- `world/poi_config.gd:152`

## Related Design Docs
- [Procedural Building Design](../design/world-generation-procedural-buildings.md)
- [World Generation and POIs](../design/world-generation-and-pois.md)

## Unknowns
- The contract does not currently expose a formal completion/event signal when generation finishes.
- Collision and navigation behavior for generated interiors is scene-template dependent and not centrally validated in this module.
