# Monster Navigation Unstuck Redesign

## Goal
Make monster patrol/chase movement robust against walls and corners by using navigation-first steering with deterministic fallback and anti-stuck recovery.

## Scope
- Keep the existing top-level AI states: WANDER, CHASE, ATTACK.
- Replace movement steering internals for WANDER and CHASE.
- Integrate NavigationAgent3D as primary path source.
- Add anti-stuck watchdog and re-path policy.
- Preserve combat, damage, loot, and targeting behavior.

## Non-Goals
- No spawn system rewrite.
- No combat balance changes.
- No group-level flocking behavior in this pass.

## Design

### 1) Navigation-First Steering Contract
- WANDER and CHASE both route through one steering helper.
- Steering helper uses NavigationAgent3D when map/path data is valid.
- If navigation is unavailable or invalid, steering falls back to direct vector movement immediately.
- ATTACK behavior remains unchanged.

### 2) Re-Path Policy
- Destination updates use a small minimum interval to avoid per-frame target thrash.
- Re-path is triggered on destination drift and on explicit stuck events.
- Re-path reset is bounded to prevent oscillation loops.

### 3) Anti-Stuck Watchdog
- When the monster intends to move but horizontal displacement remains under threshold for a configured duration, state becomes stuck.
- On stuck:
  - force a path refresh,
  - optionally apply short fallback steering window,
  - then return to navigation-first mode.
- Repeated stuck events are rate-limited by cooldown.

### 4) Data and Tuning
Add exports for:
- navigation repath interval
- movement progress threshold
- stuck detection time window
- stuck recovery cooldown
- fallback steering duration after stuck

### 5) Safety and Compatibility
- If nav map iteration is not ready, behavior degrades gracefully to direct steering.
- Existing external contracts for attack/damage/loot remain untouched.
- Existing monster scene remains compatible with added NavigationAgent3D child config.

## Testing Strategy
1. Red/Green tests for steering helper behavior:
- nav-available path direction
- nav-unavailable fallback direction
- stuck detection trigger
- stuck recovery cooldown behavior

2. Runtime script-level verification:
- Monster does not idle-lock while chasing around blockers.
- Temporary nav unavailability does not freeze movement.

3. Regression checks:
- attack cadence unchanged
- damage/loot lifecycle unchanged

## Acceptance Criteria
- Monster can navigate around common wall/corner blockers in chase state.
- Monster does not remain stalled when blocked for longer than the stuck window.
- Navigation map not-ready cases still move via fallback instead of stalling.
- No regressions to attack, damage, or loot behavior.
