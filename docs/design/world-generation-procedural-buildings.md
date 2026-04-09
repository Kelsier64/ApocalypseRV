# World Generation Procedural Buildings

## Scope
This design document explains procedural building generation used by POIs of type `procedural`, including room template ingestion, occupancy rules, BFS expansion, and elevator movement behavior.

Related contract docs:
- [Procedural Building Module](../modules/world-generation-procedural-building.md)
- [POI System Module](../modules/world-generation-poi-system.md)

## Entry Path From POI Spawn
When a POI entry has `type = procedural`, `POISpawner` creates a `Node3D`, assigns `world/building/building_generator.gd`, and sets `max_rooms` from `procedural_config` range.

Evidence:
- `world/poi_config.gd:143`
- `world/poi_config.gd:145`
- `world/poi_config.gd:150`
- `world/poi_config.gd:151`
- `world/poi_config.gd:152`
- `world/poi_spawner.gd:120`
- `world/poi_spawner.gd:123`
- `world/poi_spawner.gd:126`
- `world/poi_spawner.gd:128`

## Room Template Ingestion
`BuildingGenerator._build_room_defs()` scans `res://world/building/rooms/`, instantiates each room scene, and imports metadata only if the room instance has a positive `weight`. Imported fields are scene path, display name, `grid_size`, `weight`, and deep-copied `doors`.

Evidence:
- `world/building/building_generator.gd:25`
- `world/building/building_generator.gd:27`
- `world/building/building_generator.gd:28`
- `world/building/building_generator.gd:38`
- `world/building/building_generator.gd:39`
- `world/building/building_generator.gd:42`
- `world/building/building_generator.gd:43`
- `world/building/building_generator.gd:44`

## Grid and Occupancy Model
The procedural system uses a logical occupancy grid keyed by `Vector3i` cells. `BASE_UNIT` is 9.0 meters, so each occupied cell maps to a 9m cube in world coordinates.

Evidence:
- `world/building/building_generator.gd:4`
- `world/building/building_generator.gd:10`
- `world/building/building_generator.gd:51`
- `world/building/building_generator.gd:59`
- `world/building/room_node.gd:6`
- `world/building/room_node.gd:12`

## Expansion Algorithm
1. Reserve elevator shaft at origin as `1x4x1` cells.
2. Instantiate elevator room at origin.
3. Seed top-cell doors (`north`, `south`, `east`, `west`) at elevator top.
4. Run BFS-style frontier expansion until no open doors remain or `room_count >= max_rooms`.
5. For each frontier door, compute target cell, reject if occupied, and otherwise choose room candidates with opposite-wall compatibility.
6. Candidate ordering uses weighted random score (`pow(randf(), 1.0 / weight)`), then first fitting room is placed.
7. Any unresolved doors are sealed with CSG blockers.

Evidence:
- `world/building/building_generator.gd:66`
- `world/building/building_generator.gd:71`
- `world/building/building_generator.gd:72`
- `world/building/building_generator.gd:75`
- `world/building/building_generator.gd:88`
- `world/building/building_generator.gd:100`
- `world/building/building_generator.gd:104`
- `world/building/building_generator.gd:106`
- `world/building/building_generator.gd:112`
- `world/building/building_generator.gd:118`
- `world/building/building_generator.gd:124`
- `world/building/building_generator.gd:127`
- `world/building/building_generator.gd:139`
- `world/building/building_generator.gd:170`
- `world/building/building_generator.gd:181`

## Door and Coordinate Contracts
Door metadata relies on wall labels (`north`, `south`, `east`, `west`) plus `grid_offset`. Neighbor traversal and wall matching are implemented by `_get_target_cell()` and `_opposite_wall()`.

Evidence:
- `world/building/building_generator.gd:14`
- `world/building/building_generator.gd:104`
- `world/building/building_generator.gd:112`
- `world/building/building_generator.gd:208`
- `world/building/building_generator.gd:216`
- `world/building/room_node.gd:9`

## Elevator Platform Motion
`elevator_platform.gd` controls repeated up/down movement between `bottom_y` and `top_y`, pauses for `wait_time`, then reverses direction.

Evidence:
- `world/building/elevator_platform.gd:6`
- `world/building/elevator_platform.gd:7`
- `world/building/elevator_platform.gd:9`
- `world/building/elevator_platform.gd:15`
- `world/building/elevator_platform.gd:20`
- `world/building/elevator_platform.gd:39`

## Determinism and Limits
- `seed_value >= 0` seeds the random stream for deterministic generation from that seed.
- `max_rooms` hard-limits expansion count.

Evidence:
- `world/building/building_generator.gd:6`
- `world/building/building_generator.gd:7`
- `world/building/building_generator.gd:20`
- `world/building/building_generator.gd:100`

## Unknowns
- No explicit vertical structural validation was found beyond occupancy checks and door compatibility. Any gameplay requirements for guaranteed traversal continuity across all generated rooms are not encoded in the inspected files.
- No dedicated procedural-building test file is in this evidence set; runtime validation expectations are inferred from implementation.
