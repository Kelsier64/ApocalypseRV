# Monster Locomotion Redesign (Patrol, Jump, Climb)

## Goal
Replace the current monster locomotion internals with a stable decision layer that supports patrol/chase/attack plus deterministic obstacle traversal using walk, jump, and climb.

## Scope
- Keep top-level AI states: Patrol, Chase, Attack.
- Replace movement decision logic in chase/patrol traversal.
- Implement unified obstacle classification by geometry and height, not by object type.
- Handle floating under-surfaces (including RV undercarriage) through generic underside-edge-ledge logic.
- Keep existing combat, targeting, and loot behavior intact.

## Non-Goals
- No animation state machine integration in this pass.
- No changes to spawning system.
- No broad refactor across other gameplay scripts.

## Design

### 1) Locomotion Decision Layer
Introduce locomotion_mode with three modes:
- Ground
- Jump
- Climb

Decision priority each physics frame while moving toward a destination:
1. If path ahead is clear, stay Ground.
2. If blocked and obstacle is within jump range and top clearance is valid, use Jump.
3. If blocked and obstacle exceeds jump range but is climb candidate, use Climb.
4. If none apply, trigger short lateral reposition and retry.

### 2) Unified Obstacle Classification
Use forward probes and vertical sampling to estimate obstacle profile:
- Low probe identifies immediate frontal blockage.
- Upper probe verifies jump clearance.
- Height estimate derived from probe hit point and nearby floor sampling.

Height bands:
- Below step threshold: keep Ground.
- Between jump_min and jump_max: Jump.
- Above climb_min: Climb.

### 3) Generic Underside Handling (No RV Special Case)
Use surface normal semantics only:
- Sidewall-like normal => climb candidate.
- Downward-facing underside normal => not directly climbable.

For underside hits:
1. Run edge-seek sampling (forward-left/right offsets) to find reachable boundary.
2. From candidate boundary, run downcast to find standable landing point above obstacle.
3. Enter climb toward landing point.

This applies to all floating geometry, including RV undercarriage, suspended platforms, and overhangs.

### 4) Climb Resolution Model
Climb behavior uses "success-early, fail-hard":
- While climbing, continuously check for valid standable landing.
- If landing is found before limits, transition to Ground on landing.
- If climb exceeds max height/time, drop and enter cooldown.
- If wall contact or target is lost, drop and enter cooldown.

### 5) Stability Rules
- Jump can only trigger on floor and outside jump cooldown.
- Climb and jump are mutually exclusive modes.
- Horizontal steering persists during jump/climb with capped influence.
- Add short anti-stuck timer for repeated blocked movement.

## Data/Parameters
Add or tune exports for:
- jump_min_height
- jump_max_height
- jump_impulse
- jump_cooldown
- climb_max_height
- climb_max_duration
- climb_cooldown
- underside_normal_threshold
- edge_seek_distance
- edge_seek_side_offset
- ledge_probe_up_offset
- ledge_probe_down_distance
- stuck_reposition_time

## Testing Strategy
1. Script-level contract tests
- Locomotion helper methods exist and return expected decisions for synthetic probe inputs.
- Existing helper contracts used by tests remain compatible where practical.

2. Scene behavior checks (headless/manual)
- Monster can patrol and chase without vertical jitter.
- Small obstacle triggers jump.
- Tall obstacle triggers climb.
- Floating underside case resolves to edge seek, then climb-to-top or drop+CD.
- Repeated failures do not produce infinite climb loops.

3. Regression checks
- Attack, damage, loot, and target filtering remain unchanged.

## Risks and Mitigations
- Risk: Overly aggressive climb triggers.
  - Mitigation: strict normal and height gating plus cooldown.
- Risk: False ledge detection on noisy meshes.
  - Mitigation: standable-normal validation and landing distance caps.
- Risk: Behavior drift from existing tests.
  - Mitigation: preserve public helper surfaces where required and extend tests first.

## Implementation Notes
- User-approved approach: Keep existing AI state machine and replace locomotion internals.
- User-approved rule: Small obstacles jump, larger obstacles climb.
- User-approved climb model: Try to climb and stand when possible; otherwise fail by dropping with cooldown.
