# Monster AI Module Contract

## Module Purpose
This module controls monster AI state transitions, navigation fallback behavior, RV climbing behavior, and damage application against players and structures.

Implementation reference:
- [enemies/monster.gd](../../enemies/monster.gd#L1)

Detailed flow walk-through:
- [docs/design/climbing-and-combat-behavior.md](../design/climbing-and-combat-behavior.md)

## Top-Level State Contracts

### AI and locomotion states
- AI state enum is WANDER, CHASE, ATTACK.
- Locomotion state enum is NORMAL, CLIMBING.

Evidence:
- AI enum: [enemies/monster.gd](../../enemies/monster.gd#L90)
- Locomotion enum: [enemies/monster.gd](../../enemies/monster.gd#L94)

### Core combat tuning exports
Contract fields consumed by behavior gates:
- detection_range, attack_range, chassis_attack_range, climbing_touch_attack_range, attack_max_vertical_gap, attack_cooldown, lose_interest_range, contact_damage.

Evidence:
- Exported fields: [enemies/monster.gd](../../enemies/monster.gd#L34), [enemies/monster.gd](../../enemies/monster.gd#L37), [enemies/monster.gd](../../enemies/monster.gd#L38), [enemies/monster.gd](../../enemies/monster.gd#L39), [enemies/monster.gd](../../enemies/monster.gd#L40), [enemies/monster.gd](../../enemies/monster.gd#L44), [enemies/monster.gd](../../enemies/monster.gd#L45), [enemies/monster.gd](../../enemies/monster.gd#L46)

## Navigation and Chase Contracts

### Navigation helper surface
Expected helpers:
- _resolve_navigation_agent
- _can_use_navigation
- _get_navigation_direction
- _compute_fallback_direction
- _is_progress_too_small
- _get_frame_progress_threshold
- _update_stuck_watchdog
- _can_trigger_stuck_recovery
- _is_elevation_gap_climbable
- _build_elevation_assist_velocity
- _build_stuck_recovery_velocity

Evidence:
- Test-defined method contract: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L71), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L83)

### Chase-direction and descent hinting
Expected behavior:
- Chase direction can come from navigation or fallback vectors.
- Descent hinting uses last climb wall normal when target is significantly below.

Evidence:
- Chase direction resolver and descent injection: [enemies/monster.gd](../../enemies/monster.gd#L399), [enemies/monster.gd](../../enemies/monster.gd#L416), [enemies/monster.gd](../../enemies/monster.gd#L1480)
- Test expectations for descent hint behavior: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L111), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L183)

### Post-separation navigation gate
Expected behavior:
- Navigation for chase is blocked when on RV surface, during post-separation block, or while separated with large vertical gap.

Evidence:
- Gate function: [enemies/monster.gd](../../enemies/monster.gd#L1412)
- Test expectations: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L247), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L250)

## Climbing Contracts

### Required climb API surface
Expected helpers:
- _try_start_climb(destination)
- _process_climbing(delta, destination)
- _is_rv_wall_normal(hit_normal, rv_up)
- _get_descent_hint_direction(destination)
- _abort_climb(reason)

Evidence:
- Runtime methods: [enemies/monster.gd](../../enemies/monster.gd#L645), [enemies/monster.gd](../../enemies/monster.gd#L762), [enemies/monster.gd](../../enemies/monster.gd#L495), [enemies/monster.gd](../../enemies/monster.gd#L1480), [enemies/monster.gd](../../enemies/monster.gd#L890)
- Test method checks: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L92), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L99)

### Climb contact and target-on-RV continuity
Expected behavior:
- Climb contact grace is computed from vertical speed and clamped to configured bounds.
- Target RV presence uses current probe plus grace-based continuity.
- RV surface detection merges downward ray and overlap probe results.

Evidence:
- Grace compute and separation helper: [enemies/monster.gd](../../enemies/monster.gd#L538), [enemies/monster.gd](../../enemies/monster.gd#L546)
- Target-on-RV continuity helper: [enemies/monster.gd](../../enemies/monster.gd#L1409)
- RV surface merge helper and node probe: [enemies/monster.gd](../../enemies/monster.gd#L1511), [enemies/monster.gd](../../enemies/monster.gd#L1537)
- Test expectations: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L275), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L288), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L323)

### Climb abort policy when target leaves RV
Expected behavior:
- _should_abort_climb_when_target_leaves_rv returns true for climbing monsters when target is no longer on same RV.

Evidence:
- Runtime helper: [enemies/monster.gd](../../enemies/monster.gd#L1406)
- Test expectations: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L261), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L264)

## Combat Contracts

### Target selection contract
Expected behavior:
- Not climbing: preferred player target first, then structure priority.
- Climbing: only touching structure targets are valid combat targets.

Evidence:
- Selection function: [enemies/monster.gd](../../enemies/monster.gd#L1278)
- Climbing structure-touch filter: [enemies/monster.gd](../../enemies/monster.gd#L1049)
- Test expectations: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L430), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L454), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L506)

### Touching and underfoot attacks
Expected behavior:
- _try_auto_attack_touching_targets can attack touching player/chassis/equipment targets.
- Underfoot equipment attacks are gated by tracking-target-below checks.

Evidence:
- Auto-touch attack helper: [enemies/monster.gd](../../enemies/monster.gd#L1187)
- Underfoot gates and selector: [enemies/monster.gd](../../enemies/monster.gd#L1207), [enemies/monster.gd](../../enemies/monster.gd#L1211), [enemies/monster.gd](../../enemies/monster.gd#L1254)
- Test expectations: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L741), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L765), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L789), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L814)

### Range and LOS attack gate contract
Expected behavior:
- _can_attack_target_position_with_range enforces LOS, vertical gap, and planar range.
- Chassis targets may use chassis_attack_range.
- While climbing, touching structure targets can bypass LOS failure.

Evidence:
- Attack gate helpers: [enemies/monster.gd](../../enemies/monster.gd#L1426), [enemies/monster.gd](../../enemies/monster.gd#L1437), [enemies/monster.gd](../../enemies/monster.gd#L1443), [enemies/monster.gd](../../enemies/monster.gd#L1450)
- Test expectations for LOS override and chassis range: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L847), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L892)

### Damage execution contract
Expected behavior:
- _execute_attack_on_target requires target node validity and take_damage method.
- Successful attack applies contact_damage and starts attack cooldown.

Evidence:
- Runtime executor: [enemies/monster.gd](../../enemies/monster.gd#L960)
- Test expectation for non-player damage execution: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L864)

## Assumptions and Unknowns
- Group-registration pathways for monster_damageable, chassis, and equipment are outside this partition, so this contract describes consumption behavior only.
  Evidence: [enemies/monster.gd](../../enemies/monster.gd#L1313)
- Navigation map configuration and scene-level NavigationAgent3D placement are not defined in this partition docs set.
  Evidence: [enemies/monster.gd](../../enemies/monster.gd#L1373)
