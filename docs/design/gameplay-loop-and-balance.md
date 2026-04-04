# Design: Gameplay Loop and Balance

## 1. Intent
The core gameplay loop is built around short, repeatable actions that convert world risk into RV progress:
1. Explore streamed highway chunks.
2. Gather loot/resources while avoiding or defeating monsters.
3. Convert fuel into electrical power and materials via RV equipment.
4. Use crafted/placed tools to sustain longer exploration.

This loop prioritizes clarity and iteration speed over deep progression complexity.

## 2. Player Fantasy and Experience Targets
- Feel like a scavenger maintaining a mobile survival base.
- Constantly trade safety for resources.
- Make moment-to-moment equipment decisions based on fuel/power constraints.
- Experience pressure from enemy contact and resource scarcity.

## 3. Key Design Constraints from Implementation
- Interaction model uses timed holds and quick taps, with simple `has_method` contracts.
- Inventory is limited to 6 slots, with large-item restrictions to force carry tradeoffs.
- RV is the single source of fuel and power state.
- World content comes from weighted POI rules rather than scripted hand-authored encounters.

## 4. Resource Economy Model
- Fuel is the primary macro resource for mobility and generation.
- Power is the local operating currency consumed by equipment and charged by driving/generators.
- Scrap and material drops are transformed through scrapper/crafting interactions.
- Current implementation suggests this balance objective:
  - driving should be possible while fuel exists,
  - parked RV has small passive drain,
  - active generator smooths short-term power deficits.

## 5. Interaction Timing Design
- E hold for 1 second: heavy/hold interactions.
- E quick release: pickup/quick interaction.
- F hold for 2 seconds: equipment placement mode.

Rationale:
- Avoid accidental activation of expensive/transformative actions.
- Keep simple pickups responsive.

## 6. Combat and Threat Design
- Monster AI uses three states: WANDER, CHASE, ATTACK.
- Threat scales by proximity and attack cooldown rather than complex tactics.
- Vehicle impact damage supports emergent combat and risk-reward driving.

## 7. Tradeoffs and Known Design Debt
- Pros:
  - Fast to extend using duck-typed contracts.
  - Low ceremony for new interactables and equipment.
- Cons:
  - Limited compile-time safety and hidden contract coupling.
  - Timing-sensitive interactions are currently under-tested.
  - Balance values are script constants without telemetry feedback loop.

## 8. Future Design Hooks
- Add explicit progression milestones around RV upgrades.
- Introduce scarcity zones by POI type and distance traveled.
- Add player-visible feedback for fuel/power cause-and-effect.
- Define co-op role interactions around driving, scavenging, and base operation.

## 9. Source Files Used
- `player/player.gd`
- `player/player_interact.gd`
- `rv/chassis.gd`
- `equipment/generator.gd`
- `equipment/scrapper.gd`
- `equipment/crafting_station.gd`
- `enemies/monster.gd`
- `tests/test_energy_system.gd`
- `world/test_world.tscn`

## 10. Completeness Notes
This design doc covers gameplay intent and current balance framing from implemented systems. It does not yet define quantitative target metrics (time-to-empty-tank, expected loot per chunk, etc.).