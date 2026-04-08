# Monster Combat Target Unification Design (2026-04-08)

## Goal
Enable monsters to attack RV chassis and equipment in addition to players, and keep attack behavior active while climbing, with player-target priority preserved outside climbing.

## Scope
- Update monster combat target selection from player-only to unified combat targets.
- Preserve current AI state machine shape (WANDER/CHASE/ATTACK) and current movement/climb flow.
- Allow attack checks and attack execution during climbing.
- Add focused contract tests for target selection and climbing attack continuity.

## Non-Goals
- No aggro/threat system.
- No balancing overhaul for damage values or cooldowns.
- No scene hierarchy redesign.

## Current Baseline
- Monster currently tracks `target_player` and attack logic assumes player-only targeting.
- RV chassis and equipment already expose `take_damage` and join `monster_damageable` group.
- Climbing logic exists and is robust, but attack execution is not unified with climb flow for non-player targets.

## Requirements
1. Monster can select RV chassis or equipment as valid combat targets when in range/LOS.
2. Player has higher target priority than chassis/equipment when simultaneously available.
3. Attack gate logic (range, vertical gap, line-of-sight) remains enforced for all target types.
4. Monster continues to evaluate and execute attacks while in climbing locomotion state, but climbing attacks should target chassis/equipment only (no player attacks while climbing).
5. While climbing, monster target selection is restricted to touching-range chassis/equipment and always picks the nearest touched target.
6. Existing navigation/unstuck/vehicle-collision behavior remains unchanged.

## Design

### 1) Unified Combat Target Model
Add a lightweight internal combat-target representation in monster logic (dictionary-like payload) with:
- `node`: target node
- `position`: target world position snapshot
- `target_type`: `player`, `chassis`, or `equipment`

This avoids new file/module overhead while still separating target acquisition from attack execution.

### 2) Target Acquisition Pipeline
Introduce helper flow in monster script:
- Gather candidate players from `player` group.
- Gather candidate structures from `monster_damageable` group (excluding self and invalid nodes).
- Filter by attack/detection constraints and LOS.
- Apply deterministic priority for normal (non-climbing) combat:
  1. player
  2. chassis/equipment
  3. nearest within same priority class

Store selected target as `current_combat_target` and keep `target_player` for backward-compatible chase behavior where needed.

### 3) Unified Attack Execution
Refactor `_process_attack` into generic logic:
- Face `current_combat_target.position`.
- On cooldown expiry, call `take_damage(contact_damage)` on target node if still valid.
- Keep existing cooldown and print/debug style.

### 4) Climbing Integration
In climbing branch:
- Continue refreshing `current_combat_target` every frame.
- Reuse the same attack gate and attack executor while still processing climb motion.
- While climbing, filter out player targets so only chassis/equipment remain attackable.
- While climbing, only consider chassis/equipment inside a configurable touch range and select the nearest touched target.
- Do not force locomotion state exit to attack.

This keeps movement and combat decoupled and avoids climb regressions.

### 5) Safety/Regression Controls
- Keep existing state enum and core transitions.
- Do not alter vehicle-to-monster collision damage system.
- Do not change loot/death path.
- Guard all target calls with instance validity checks.

## Testing Plan (TDD)
1. Add failing test: unified target helper can accept chassis/equipment targets.
2. Add failing test: player priority wins over structure targets when both valid.
3. Add failing test: attack executor can damage a non-player target.
4. Add failing test: while climbing, player targets are excluded from attack selection.
5. Add failing test: climbing state still allows attack execution path against chassis/equipment.
6. Run monster navigation contract tests to ensure no regressions.

## Acceptance Criteria
- Monster damages chassis/equipment when player is not selected or unavailable.
- Monster still prioritizes player when both are valid.
- Monster can attack while climbing without forced drop to normal locomotion.
- While climbing, monster only attacks nearest touched chassis/equipment target.
- Monster does not attack player while climbing.
- New tests pass and existing monster navigation tests remain green.
