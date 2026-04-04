# Design: Procedural Generation and Content

## 1. Intent
The procedural content strategy creates a long-travel highway experience where each chunk offers familiar navigation with varied side content.

## 2. Design Goals
- Keep driving route legible and drivable.
- Inject optional risk/reward via POIs.
- Blend authored scenes and procedural structures in the same spawn pipeline.
- Keep content generation deterministic enough to reason about but varied enough to replay.

## 3. World Shape Strategy
- Chunks are generated as connected segments with Bezier-based road curvature.
- Road slopes are constrained to avoid unrealistic tilt.
- Terrain is noise-based with local blending around roads and POI footprints.
- Chunks behind player are discarded to keep memory bounded.

## 4. POI Content Strategy
- Weighted POI table controls encounter frequency.
- Each POI carries its own footprint, road distance, loot table, and enemy rules.
- Gridmap POIs provide authored landmarks.
- Procedural tower POI uses room templates and occupancy-aware expansion for structural variety.

## 5. Interior Generation Strategy
- Elevator acts as anchor room.
- BFS expansion from open doors grows layout until room cap.
- Candidate rooms are weighted and validated against occupancy grid.
- Unmatched doors are sealed to maintain structural consistency.

## 6. Tradeoffs and Constraints
- Strengths:
  - Fast content iteration through config tables and scene resources.
  - Good blend of predictable navigation and stochastic encounters.
- Constraints:
  - Missing scene files silently reduce content diversity.
  - No current deterministic seed pipeline exposed for world replay/debug sessions.
  - Heavy mesh generation cost per chunk may limit scalability.

## 7. Failure Patterns to Watch
- Overly aggressive chunk generation causing frame spikes.
- POI sparsity if min road distance and candidate random ranges conflict.
- Procedural interiors over-sealing if room templates lack door compatibility.

## 8. Future Design Hooks
- Biome or district layers that modify POI weight tables by distance.
- Deterministic run seeds surfaced in UI for reproducible sessions.
- Difficulty scaling by chunk index and resource pressure curves.

## 9. Source Files Used
- `world/world_generator.gd`
- `world/chunk_generator.gd`
- `world/poi_spawner.gd`
- `world/poi_config.gd`
- `world/building/building_generator.gd`
- `world/building/room_node.gd`
- `world/test_world.tscn`

## 10. Completeness Notes
This document captures current procedural design intent and implementation-aligned tradeoffs. It does not include formal generation KPIs or profiling baselines yet.