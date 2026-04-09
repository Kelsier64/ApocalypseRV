# Monster Underfoot Attack Redesign (Raycast Single Path)

Date: 2026-04-09

## 1. Goal
Stabilize monster underfoot equipment attacks by enforcing one deterministic behavior path and removing legacy ambiguity that caused repeated regressions.

Primary behavior intent:
- Underfoot equipment attack can happen only when a downward underfoot raycast hits a valid floor equipment target.
- Underfoot attack is additionally gated by player tracking elevation (tracked player must be lower than the monster by margin).

## 2. Locked Product Decisions
The following decisions are fixed for this redesign:
1. Underfoot target detection is raycast-only (UnderfootProbe hit required).
2. Tracking authorization source is player-only.
3. Underfoot attack target type is floor equipment only (exclude player and chassis).
4. Legacy candidate-list fallback is removed completely, including test semantics.

## 3. Scope
In scope:
- Monster underfoot detection and authorization flow.
- Zombie scene probe wiring required by the flow.
- Monster navigation contract tests that define underfoot behavior.

Out of scope:
- RV energy, world generation, and player climbing mechanics.
- Broad monster state machine redesign unrelated to underfoot selection.

## 4. Architecture and Invariants
This redesign defines a strict layered flow with one responsibility per layer.

### 4.1 Detection Layer (Probe)
Responsibility:
- Resolve and evaluate UnderfootProbe hit.

Invariant:
- If no valid raycast hit exists, underfoot attack path must terminate with no attack.

### 4.2 Target Resolution Layer
Responsibility:
- Convert probe collider to nearest valid Node3D damage target via parent walk.
- Validate target as floor equipment (damageable, not player, not chassis).

Invariant:
- Chassis and player cannot pass as underfoot equipment targets.

### 4.3 Authorization Layer
Responsibility:
- Evaluate whether tracked player position is below monster by configured margin.

Invariant:
- Authorization source is player-only; structure targets cannot authorize underfoot attacks.

### 4.4 Execution Layer
Responsibility:
- Execute damage only when both resolution and authorization succeed.

Invariant:
- Underfoot path performs no candidate-distance fallback and no implicit substitutions.

## 5. Runtime Data Flow
1. Monster update enters auto-attack phase.
2. Underfoot sub-flow resolves tracking source using player-only rules.
3. Underfoot sub-flow resolves downward raycast hit from UnderfootProbe.
4. Hit collider is translated to first valid floor equipment damageable node.
5. Authorization checks tracked player lower-than-monster gate.
6. If steps 3-5 all pass, attack executes through existing attack executor.
7. If any step fails, underfoot attack returns no-op.

Note:
- Touching attack flow remains separate and does not provide fallback input to underfoot selection.

## 6. Error Handling and Safety
Expected no-op behavior (not errors):
- Missing probe node.
- Probe exists but no collision.
- Hit collider resolves only to non-equipment types.
- No tracked player source.
- Tracked player is not below monster.

Safety rules:
- Prefer silent no-op over speculative target guessing.
- Keep underfoot and touching contracts isolated to reduce cross-path regressions.

## 7. Test Contract Redesign
Legacy semantics to remove:
- Any test expectation that allows underfoot target selection without raycast hit.
- Any expectation that structure targets can authorize underfoot attacks.

Required underfoot tests:
1. Probe resolver binds UnderfootProbe correctly.
2. Raycast hit + valid equipment + player-below => attack allowed.
3. Raycast hit + valid equipment + player-not-below => attack blocked.
4. No raycast hit => attack blocked.
5. Raycast hit to chassis/player => underfoot equipment attack blocked.
6. Non-player tracking source => underfoot authorization blocked.

Required regression guard:
- Existing touching attack tests stay green to confirm no accidental behavioral drift.

## 8. File-Level Change Boundary
Planned implementation boundary:
- enemies/monster.gd
- enemies/zombie.tscn
- tests/test_monster_navigation.gd

No additional module/doc refactors are required for this specific redesign.

## 9. Acceptance Criteria
Implementation is complete only when all are true:
1. Underfoot legacy fallback path is fully removed.
2. Underfoot attack is raycast-hit-driven only.
3. Underfoot authorization is player-only and lower-than-monster gated.
4. Chassis is excluded from underfoot equipment target class.
5. tests/test_monster_navigation.gd passes with updated contract expectations.

## 10. Non-Goals
- No balancing changes to attack damage/cooldown values.
- No redesign of global combat target priorities beyond underfoot contract isolation.
- No expansion of underfoot behavior to chassis attack cases.
