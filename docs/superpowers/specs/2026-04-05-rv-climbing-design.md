# RV Climbing Design (2026-04-05)

## Goal
Allow the player to climb onto the RV by pressing jump while holding W against an RV wall, including while the RV is moving, with strong anti-bug safeguards against launch/fly/glitch behavior. Reaching the top must place the player stably onto the roof surface.

## Scope
In scope:
- Player climbing state flow and wall-trigger rules.
- Moving-RV compensation during climb and mantle.
- Top-out (mantle) logic that guarantees valid standing placement.
- Regression tests for climbing gate logic and RV-motion compensation math.

Out of scope:
- Changes to RV fuel/power systems.
- Changes to seat driving flow.
- Broad refactors of interaction or inventory subsystems.

## Constraints
- RV chassis is elevated, so climb detection cannot rely on generic RV proximity.
- Trigger requirement: jump + W + wall contact.
- Climbing a moving RV is high-risk for physics instability (launching/flying).
- Top transition to roof standing is a critical bug hotspot and must be explicitly gated.

## Selected Approach
Approach B: Player state machine with dual-gate wall/top checks and RV-frame compensation.

Rationale:
- More robust than a minimal single-check approach.
- Avoids scene-heavy trigger-volume maintenance burden.
- Keeps changes mostly in player movement code while explicitly handling moving-platform edge cases.

## High-Level Architecture
Add player locomotion sub-states:
1. Normal
2. Climbing
3. Mantling

State transitions:
- Normal -> Climbing only when jump-press + W-hold + valid RV wall hit pass all gates.
- Climbing -> Mantling only when top surface and stand-space checks both pass.
- Mantling -> Normal after interpolation completes and player lands in a validated stand position.
- Climbing/Mantling -> Normal fallback when safety conditions fail.

## Detection Model
### Wall Gate (enter climb)
All must pass:
1. Jump pressed this frame.
2. W currently held.
3. Forward wall probe hits collider belonging to RV hierarchy.
4. Hit normal is near-vertical wall (not floor/roof/underside).
5. Hit point vertical window is in valid body-height range (avoids undercarriage false positives).

### Top Gate (start mantle)
All must pass:
1. A forward/up probe identifies a standable top plane with up-aligned normal.
2. Candidate stand position has enough capsule clearance.
3. Immediate forward overlap/sweep does not report blocking penetration.

## Moving RV Stability Strategy
During Climbing and Mantling:
- Track the active RV reference and previous RV global transform.
- Per frame, apply RV transform delta compensation to player position.
- Keep climb motion in RV-local reference where possible.

Safety guards:
- Clamp max per-frame climb displacement.
- Clamp vertical climb velocity.
- If wall contact is lost beyond a short grace time, abort to Normal.
- If RV angular velocity exceeds a safety threshold, abort climb/mantle.
- On mantle completion or forced exit, sanitize player velocity (reset risky vertical impulse).

## Top-Out and Stand Placement
Mantle flow:
1. Compute a safe target stand transform on roof plane.
2. Interpolate player from wall anchor to stand target over short duration.
3. Disable standard locomotion impulses during mantle.
4. Continue RV-delta compensation during mantle interpolation.
5. Finish only if final stand probe still valid; otherwise cancel to safe fallback.

Fallback behavior:
- If final stand validation fails, drop to Normal with stable velocity and without teleport spikes.

## Files to Change
Primary:
- player/player.gd: add climb/mantle states, probes, transitions, RV compensation, safety guards.
- player/player.tscn: add dedicated RayCast nodes for wall and top checks.

Tests:
- tests/test_player_climbing.gd (new): gate logic, undercarriage rejection, top-gate validation, RV-delta compensation math.

Docs:
- docs/modules/player-equipment-interactions.md: update movement interaction section with climb controls and safeguards.

## Behavioral Requirements
1. Static RV wall:
- Jump + W against RV wall enters climb.
- Player can ascend and top-out to roof stably.

2. Moving RV wall:
- Climb remains attached to RV motion frame.
- No launch/fly due to transform desync.

3. Undercarriage zone:
- No false climb trigger from below chassis gaps.

4. Top transition:
- Player stands on roof with valid capsule clearance.
- No clipping into wall/ceiling and no sudden upward impulse.

## Test Plan (TDD)
1. Write failing tests for climb enter gates.
2. Verify fail reasons are missing climb implementation.
3. Implement minimal gate logic to pass.
4. Write failing tests for top gate + stand clearance.
5. Implement minimal top-out checks to pass.
6. Write failing tests for RV delta compensation and velocity sanitize on exit.
7. Implement minimal compensation and exit safeguards to pass.
8. Run targeted tests then broader regression tests.

## Risks and Mitigations
1. Physics jitter from mixed world/local spaces.
- Mitigation: apply RV delta once per frame in a single controlled branch.

2. Edge cases on tilted RV orientation.
- Mitigation: evaluate wall/top normals relative to RV up vector where required.

3. False positives around corners.
- Mitigation: combine normal thresholds with hit window and collider ancestry checks.

4. Mantle destination invalidated mid-transition.
- Mitigation: revalidate near completion and fall back safely.

## Acceptance Criteria
- Trigger uses jump + W + RV wall contact.
- No undercarriage-trigger climbing.
- Moving RV climb works without fly/launch behavior.
- Top-out places player on roof plane reliably.
- New climbing tests pass in headless run.
