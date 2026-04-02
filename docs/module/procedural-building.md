# Module: Procedural Building

## 1. Responsibility
- Generate procedural multi-room structures for procedural POIs using a grid occupancy model.
- Start from a fixed elevator core and expand rooms via weighted BFS-compatible door matching.
- Seal unresolved open doors with collision-enabled blockers.

## 2. Boundaries and Dependencies
- Boundaries:
  - Triggered by POI spawner; does not choose POI placement itself.
  - Does not manage chunk streaming lifecycle.
- Dependencies:
  - Room scene metadata in `world/building/rooms/*.tscn` via `RoomNode` exports.
  - `elevator.tscn` as mandatory anchor room.

## 3. Entry Points and Public Surface
- `_ready()` initializes room definitions, optional seed, and calls `generate()`.
- `generate()` is the primary build pipeline.
- Utility methods used internally:
  - `can_place_room`, `reserve_cells`
  - `_get_target_cell`, `_opposite_wall`

## 4. Internal Structure
| Part | Role | Key Symbols | File |
|---|---|---|---|
| Generator core | BFS room expansion and sealing | `generate`, `open_doors`, `doors_to_seal` | `world/building/building_generator.gd` |
| Room metadata class | Exposes room shape/weight/doors contract | `room_name`, `weight`, `grid_size`, `doors` | `world/building/room_node.gd` |
| Elevator mover | Animates lift platform in elevator room | `bottom_y`, `top_y`, `speed`, `_physics_process` | `world/building/elevator_platform.gd` |
| Room assets | Candidate room prefabs with metadata | `*.tscn` under rooms/ | `world/building/rooms/*.tscn` |

## 5. Control Flow
### Main flow
1. `_build_room_defs` scans room directory and loads only scenes with `weight > 0` into candidates.
2. `generate` reserves elevator footprint at origin and instantiates elevator scene.
3. Open doors queue starts from elevator top cell on four cardinal walls.
4. For each open door, generator computes target cell and searches weighted candidate rooms with opposite wall door match.
5. First candidate that fits occupancy is placed; new doors are queued; process repeats until queue empty or `max_rooms` reached.
6. Remaining unresolved doors are sealed by creating CSG blockers.

### Error flow
1. Room scene fails to load during defs scan: entry is skipped.
2. Candidate room cannot fit occupancy: candidate rejected and next candidate tried.
3. No candidate fits a door: door recorded for seal generation.

## 6. Data Contracts
- Occupancy grid keys are `Vector3i` cells in units of `BASE_UNIT` (9m).
- Room definition dictionary expects:
  - `scene`, `name`, `grid_size`, `weight`, `doors`.
- Door entries expect:
  - `wall: String` in `{north,south,east,west}`.
  - `grid_offset: Vector3i` relative to room origin.
- Elevator is assumed to occupy `Vector3i(1,4,1)` from origin.

## 7. Configuration Touchpoints
- `BASE_UNIT = 9.0` defines world scale per occupancy cell.
- Exported tuning:
  - `max_rooms` (default 20)
- `seed_value` (`-1` uses random sequence, non-negative seeds deterministic call to `seed(seed_value)`).
- Procedural POI may override room count range through POI spawner.

## 8. Failure Modes and Safeguards
- Safeguards:
  - Occupancy checks prevent room overlap at cell level.
  - Door sealing ensures unresolved openings are blocked physically.
- Failure modes:
  - Misconfigured room door metadata can produce unreachable or illogical layouts.
  - Known door sealing behavior has correctness issues for some expected sealed/unsealed combinations.
  - Frequent runtime scene loading in large expansions can add performance overhead.

## 9. Testing and Verification
- Existing tests: none.
- Missing tests:
  - Property-based checks for overlap absence and door consistency.
  - Reproducibility checks with fixed `seed_value`.
  - Structural validity checks for path connectivity from elevator to placed rooms.
- Quick verification commands:
  - `godot --path . res://world/test_world.tscn`
  - Manual repeated spawn observation of procedural towers in runtime.

## 10. Change Checklist
- [ ] API contract checked
- [ ] Backward compatibility checked
- [ ] Docs consistency checked
- [ ] Tests updated or justified

## 11. Source Files Used
- `world/building/building_generator.gd`
- `world/building/room_node.gd`
- `world/building/elevator_platform.gd`
- `world/building/rooms/elevator.tscn`
- `world/building/rooms/standard_room.tscn`
- `world/building/rooms/corridor.tscn`
- `world/building/rooms/long_room.tscn`
- `world/building/rooms/large_hall.tscn`
- `world/building/rooms/tall_room.tscn`
- `world/poi_spawner.gd`

## 12. Completeness Notes
- This module doc covers currently implemented procedural building generation and room metadata contracts.
- It does not define any editor tooling for authoring new room metadata beyond existing script exports.
