# Module: Enemy AI and Combat

## 1. Responsibility
- Implement enemy locomotion and simple behavior state machine (wander/chase/attack).
- Apply damage to player targets and receive damage from player/vehicle.
- Spawn loot props on enemy death.

## 2. Boundaries and Dependencies
- Boundaries:
  - Does not own spawn scheduling (spawned by world/POI chunk systems).
  - Does not control player health UI rendering internals, only calls player damage API.
- Dependencies:
  - Player group membership (`player`) for target selection.
  - Prop scene for loot instantiation.
  - Vehicle collisions via `HitBox` area callback.

## 3. Entry Points and Public Surface
- Public enemy methods/events:
  - `_physics_process(delta)` state machine driver
  - `take_damage(amount)`
  - `die()`
  - `_on_hitbox_body_entered(body)` vehicle impact path
- Scene-level configuration (`zombie.tscn`):
  - Exports tuned for zombie archetype (`max_health`, `move_speed`, `contact_damage`, `loot_drops`).

## 4. Internal Structure
| Part | Role | Key Symbols | File |
|---|---|---|---|
| Monster base behavior | State machine, movement, attacks, death/loot | `State`, `_process_wander`, `_process_chase`, `_process_attack` | `enemies/monster.gd` |
| Zombie prefab | Concrete monster tuning and visuals | exported values in scene | `enemies/zombie.tscn` |

## 5. Control Flow
### Main flow
1. `_ready()` initializes health, group membership, hitbox callback, and initial wander direction.
2. Each physics tick updates gravity, attack cooldown, and resolves current AI state.
3. If target absent, nearest player in `player` group is queried.
4. In ATTACK state and cooldown ready, enemy calls `target_player.take_damage(contact_damage)`.
5. On death, loot is rolled/spawned and enemy scales down before `queue_free`.

### Error flow
1. No player found in group: enemy remains in non-targeted behavior path.
2. Loot scene load failure: death proceeds without loot spawn.
3. Invalid target reference: state transitions back toward wander/chase fallback.

## 6. Data Contracts
- Player contract: target must implement `take_damage(amount)` for attack to apply.
- Loot contract:
  - `loot_drops` dictionary values are quantity ranges (`Vector2`) per material key.
  - Spawned loot prop should expose `scrap_yields` settable property.
- Vehicle collision contract:
  - Any `VehicleBody3D` entering hitbox applies speed-scaled damage.

## 7. Configuration Touchpoints
- AI tuning exports:
  - `detection_range`, `attack_range`, `attack_cooldown`, `lose_interest_range`.
- Movement/combat exports:
  - `move_speed`, `contact_damage`, `max_health`.
- Loot tuning exports:
  - `loot_scene`, `loot_drops`.

## 8. Failure Modes and Safeguards
- Safeguards:
  - `is_dead` guard in all major paths prevents double processing.
  - Attack uses cooldown timer to prevent per-frame damage spam.
  - Null/valid checks around target and scene loads avoid hard crashes.
- Failure modes:
  - Fallback branch in `_find_nearest_player` is effectively empty; if groups are misconfigured targeting fails silently.
  - Interpolated transform rotation may produce non-physical-looking orientation on abrupt movement.
  - Damage feedback assumes mesh material override exists; missing override removes visual flash but not logic.

## 9. Testing and Verification
- Existing tests: none.
- Missing tests:
  - Deterministic state transition tests (wander->chase->attack->chase).
  - Attack cooldown correctness and player damage integration.
  - Vehicle collision damage scaling sanity checks.
  - Loot roll bounds and spawn validity checks.
- Quick verification commands:
  - `godot --path . res://world/test_world.tscn`

## 10. Change Checklist
- [ ] API contract checked
- [ ] Backward compatibility checked
- [ ] Docs consistency checked
- [ ] Tests updated or justified

## 11. Source Files Used
- `enemies/monster.gd`
- `enemies/zombie.tscn`
- `player/player.gd`
- `world/chunk_generator.gd`
- `world/poi_spawner.gd`

## 12. Completeness Notes
- This module doc covers currently implemented enemy logic and integration touchpoints.
- Additional enemy archetypes beyond zombie are not present in scanned source and therefore not documented as implemented.
