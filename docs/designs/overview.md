# Design Overview

## Scope and Current Feature Areas
- Current implemented scope is a single-player-first runtime loop in `res://world/test_world.tscn`: player control, RV driving, prop looting, equipment placement, basic crafting/scrapping, enemy combat, and procedural chunk generation.
- Core feature areas in code:
  - Player control, inventory, health, and interaction ray workflows.
  - RV chassis with wheel slot system and material inventory.
  - Equipment devices (driver seat, scrapper, crafting station, tablet UI).
  - World generation pipeline (streaming chunks, roads/terrain, POI spawning, procedural buildings).
  - Enemy AI with simple state machine and loot drop.
- Out-of-scope from current implementation despite mentions in `GDD.md`: multiplayer networking, proximity voice, advanced weather/day-night systems, and persistent meta progression.

## Design Principles and Non-Goals
### Design principles
- **Composable node systems**: prefer scene composition and script specialization over monolithic managers.
- **Duck-typed integration**: systems interact through `has_method` and group discovery to avoid tight script coupling.
- **Playable-first iteration**: mechanics are implemented with direct runtime feedback and logs, prioritizing loop completeness over infrastructure.
- **Safety over realism in placement**: placement flow aggressively disables collisions and adds exceptions to prevent physics explosions.

### Non-goals
- Not designing for strict compile-time interfaces at this stage.
- Not optimizing for deterministic replay or authoritative simulation.
- Not pursuing a polished production UX across all edge cases yet.

## Cross-Cutting Concerns
### Security
- No network boundary exists in scanned code; primary risk surface is local script misuse and invalid scene wiring.
- Duck-typed calls can hide contract violations until runtime; safety depends on scene discipline.

### Performance
- High-cost hotspots are runtime mesh and collision generation per chunk (`SurfaceTool` + `ConcavePolygonShape3D`).
- Streaming cadence can cause frame spikes when spawning/despawning and when POIs instantiate heavy scenes.
- Procedural building generation does scene loads and BFS expansion at runtime.

### Reliability
- Subsystems are resilient to missing references via guard clauses and fallback behavior.
- Known fragile areas: POI scenes missing from table paths, wheel-hitbox parent-chain assumptions, and building door sealing anomalies.

### Observability
- Debugging is currently print-driven; no centralized telemetry or structured event stream exists.
- Operational visibility relies on targeted logs in generator/combat/inventory/device scripts.

## Planned Milestones
1. **Milestone 1: Contract hardening and validation**
   - Add startup/runtime assertions for critical duck-typed interfaces and group membership.
   - Add POI asset validation pass for every `POIConfig` entry.
2. **Milestone 2: World generation stability and profiling**
   - Profile chunk generation and concave collision costs under sustained driving.
   - Add lightweight runtime counters for chunk lifecycle and generation timings.
3. **Milestone 3: Gameplay loop depth**
   - Expand crafting recipes and resource sinks (fuel/power consumption linkage).
   - Improve enemy variety and balancing around POI density.
4. **Milestone 4: Content and tooling consistency**
   - Align procedural building sealing behavior with intended room-door contracts.
   - Standardize scene creation workflow for generated assets (`generate_store.gd` style scripts where appropriate).

## Known Risks and Follow-Up Tasks
- **Risk**: `POIConfig` references scenes not present in `world/building/scenes/` (`rest_stop`, `apartment`, `warehouse`, `bunker`).
  - Follow-up: either add those scenes or adjust table entries to valid assets.
- **Risk**: `WorldGenerator` uses exported variable `player` for streaming position while design notes often expect RV/chassis tracking.
  - Follow-up: lock a single authoritative tracker and enforce scene assignment checks.
- **Risk**: health UI flashes red on any health update, including non-damage updates.
  - Follow-up: split "damage flash" from generic health repaint path.
- **Risk**: No automated tests means regressions are likely when changing interaction contracts.
  - Follow-up: add at least headless script-level smoke checks for critical flows.

## Source Files Used
- `GDD.md`
- `project.godot`
- `world/test_world.tscn`
- `player/player.gd`
- `player/player_interact.gd`
- `rv/chassis.gd`
- `equipment/equipment.gd`
- `equipment/driver_seat.gd`
- `equipment/scrapper.gd`
- `equipment/tablet_ui.gd`
- `world/world_generator.gd`
- `world/chunk_generator.gd`
- `world/poi_config.gd`
- `world/poi_spawner.gd`
- `world/building/building_generator.gd`
- `enemies/monster.gd`
