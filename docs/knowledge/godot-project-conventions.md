# Knowledge: Godot Project Conventions

## 1. Why This Matters
This project relies on consistent scene/script contracts and runtime assumptions. Capturing conventions prevents regressions when adding content or systems.

## 2. Trigger Conditions
Use this reference when:
- Adding new interactable props/equipment.
- Extending world generation or POI entries.
- Wiring player/enemy/RV integrations.
- Creating or updating tests for gameplay contracts.

## 3. Canonical Workflow
1. Place new scripts/scenes under existing domain folders (`player`, `rv`, `equipment`, `world`, `props`, `enemies`).
2. Reuse established method/group contracts instead of adding ad-hoc hard references.
3. Prefer exported variables for tuning values.
4. Verify flow in `world/test_world.tscn` and update docs/modules if contracts change.

## 4. Commands/APIs/Procedures
Core contract conventions:
- Interaction contracts:
  - `interact(player)` for quick action.
  - `interact_hold(player)` with `hold_timer` for hold actions.
- RV group and contracts:
  - RV nodes use group `rv`.
  - Equipment uses duck-typed checks for methods like `consume_power`, `add_item`, `deduct_materials`.
- Generator integration:
  - Generator nodes join `rv_power_generators` and expose `generate_power(rv, delta)`.
- Player group:
  - Player joins `player` group for enemy targeting.

## 5. Source Types
- Script-level contracts from gameplay modules.
- Scene composition from test world scene.
- Test script assertions for API expectations.

## 6. Edge Cases and Failure Patterns
- Duck typing allows flexibility but can hide incompatible changes until runtime.
- Scene path typos in POI config quietly reduce spawn variety.
- Group membership omissions break cross-system discovery (enemy player targeting, RV equipment linking).
- Interaction timing changes can alter behavior across many props if not validated.

## 7. Validation Checklist
- [ ] New interactable follows `interact` or `interact_hold` contract.
- [ ] RV-connected equipment can find a parent in group `rv`.
- [ ] Any generator-like module joins `rv_power_generators`.
- [ ] Added POI scene paths exist and load successfully.
- [ ] Any contract change is reflected in docs under `docs/modules/`.

## 8. Related Modules
- `docs/modules/player-and-interaction.md`
- `docs/modules/world-generation.md`
- `docs/modules/rv-energy-and-equipment.md`

## 9. Source Materials Used
- `world/test_world.tscn`
- `player/player.gd`
- `player/player_interact.gd`
- `rv/chassis.gd`
- `equipment/equipment.gd`
- `equipment/generator.gd`
- `world/poi_spawner.gd`
- `world/poi_config.gd`
- `enemies/monster.gd`
- `tests/test_energy_system.gd`

## 10. Completeness Notes
This convention guide captures currently visible patterns and contracts. It should be updated when stronger typing, formal interfaces, or new subsystem boundaries are introduced.