# Climbing and Combat Behavior

## Scope
This document describes climb-state transitions, climb motion constraints, and monster combat behavior that are implemented in the current partition source files.

Primary references:
- Player traversal and climb state logic in [player/player.gd](../../player/player.gd#L51)
- Monster locomotion, chase, climb, and attack logic in [enemies/monster.gd](../../enemies/monster.gd#L90)
- Contract-defining tests in [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L30), [tests/test_player_climbing_runtime.gd](../../tests/test_player_climbing_runtime.gd#L18), and [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L71)

## Player Climb Lifecycle

### Entry gates
Player climb entry runs only from NORMAL locomotion and requires active forward input, valid RV wall probe contact, acceptable wall normal, acceptable hit height, and enough upward clearance.

Evidence:
- Locomotion states and default state: [player/player.gd](../../player/player.gd#L51), [player/player.gd](../../player/player.gd#L52)
- Start helper and NORMAL-only gate: [player/player.gd](../../player/player.gd#L488), [player/player.gd](../../player/player.gd#L489)
- Re-enter cooldown gate: [player/player.gd](../../player/player.gd#L491)
- Forward key requirement: [player/player.gd](../../player/player.gd#L494)
- Ceiling-clearance gate at start: [player/player.gd](../../player/player.gd#L509)
- Wall-normal and hit-height gates: [player/player.gd](../../player/player.gd#L526), [player/player.gd](../../player/player.gd#L527)
- Transition to CLIMBING: [player/player.gd](../../player/player.gd#L542)

### In-climb behavior and abort conditions
While climbing, player movement uses climb-specific motion composition and can abort for invalid RV, manual detach input, high RV angular velocity, ceiling block, or expired wall-contact grace.

Evidence:
- Climb update loop: [player/player.gd](../../player/player.gd#L570)
- RV validity abort: [player/player.gd](../../player/player.gd#L572)
- Manual detach on S or jump action: [player/player.gd](../../player/player.gd#L576)
- Angular-velocity safety abort: [player/player.gd](../../player/player.gd#L582)
- Ceiling block during climb: [player/player.gd](../../player/player.gd#L612), [player/player.gd](../../player/player.gd#L627)
- Motion builder use: [player/player.gd](../../player/player.gd#L638)
- Lost-contact abort: [player/player.gd](../../player/player.gd#L645)
- Abort handler: [player/player.gd](../../player/player.gd#L647)

### Exit behavior
Climb exit always restores NORMAL locomotion, clears climb references, applies re-enter cooldown, and sanitizes upward velocity.

Evidence:
- Exit state reset: [player/player.gd](../../player/player.gd#L664)
- Re-enter cooldown applied: [player/player.gd](../../player/player.gd#L668)
- Exit velocity sanitizer call: [player/player.gd](../../player/player.gd#L670)
- Sanitizer contract: [player/player.gd](../../player/player.gd#L325)

## Monster Climb-Chase-Combat Lifecycle

### State model and chase integration
Monster behavior combines AI state (WANDER, CHASE, ATTACK) with locomotion state (NORMAL, CLIMBING). Chase attempts can trigger climb start when climb prerequisites are met.

Evidence:
- AI state enum: [enemies/monster.gd](../../enemies/monster.gd#L90)
- Locomotion enum: [enemies/monster.gd](../../enemies/monster.gd#L94)
- Chase attempts climb start: [enemies/monster.gd](../../enemies/monster.gd#L344)
- Climb start helper: [enemies/monster.gd](../../enemies/monster.gd#L645)

### Climb continuity and separation handling
During climbing, monster maintains wall contact with probe plus fallback contact checks, tracks separation state, and aborts if target leaves RV (after grace policy) or climb constraints fail.

Evidence:
- Climb loop: [enemies/monster.gd](../../enemies/monster.gd#L762)
- Fallback contact helper: [enemies/monster.gd](../../enemies/monster.gd#L730)
- Contact grace computation: [enemies/monster.gd](../../enemies/monster.gd#L538)
- Separation state labels: [enemies/monster.gd](../../enemies/monster.gd#L546), [enemies/monster.gd](../../enemies/monster.gd#L816)
- Target-on-RV probe and grace merge: [enemies/monster.gd](../../enemies/monster.gd#L775), [enemies/monster.gd](../../enemies/monster.gd#L778), [enemies/monster.gd](../../enemies/monster.gd#L1409)
- Abort when target leaves RV: [enemies/monster.gd](../../enemies/monster.gd#L832), [enemies/monster.gd](../../enemies/monster.gd#L845), [enemies/monster.gd](../../enemies/monster.gd#L1406)

### Post-separation steering policy
When climb exits because wall contact is lost, monster applies a temporary navigation block and short transfer vector bias before fully returning to normal chase steering.

Evidence:
- Post-separation block constant: [enemies/monster.gd](../../enemies/monster.gd#L27)
- Transfer-time constant: [enemies/monster.gd](../../enemies/monster.gd#L23)
- Exit path sets block and transfer direction on lost contact: [enemies/monster.gd](../../enemies/monster.gd#L906), [enemies/monster.gd](../../enemies/monster.gd#L921), [enemies/monster.gd](../../enemies/monster.gd#L925)
- Chase-direction blend with transfer direction: [enemies/monster.gd](../../enemies/monster.gd#L421), [enemies/monster.gd](../../enemies/monster.gd#L426)
- Navigation gate after separation: [enemies/monster.gd](../../enemies/monster.gd#L1412)

## Monster Attack Behavior

### Target selection policy
- Not climbing: player target is preferred over structure targets.
- Climbing: only touching structure targets are selected.

Evidence:
- Selection function: [enemies/monster.gd](../../enemies/monster.gd#L1278)
- Touching structure filter for climbing: [enemies/monster.gd](../../enemies/monster.gd#L1049), [enemies/monster.gd](../../enemies/monster.gd#L1097)
- Auto-touch attack pass each physics update: [enemies/monster.gd](../../enemies/monster.gd#L218), [enemies/monster.gd](../../enemies/monster.gd#L1187)

### Attack gates
Attacks are constrained by line of sight and vertical gap/range checks, with one explicit exception: while climbing, touching structure targets can bypass LOS blocking.

Evidence:
- Attack processing flow: [enemies/monster.gd](../../enemies/monster.gd#L936)
- LOS ray helper: [enemies/monster.gd](../../enemies/monster.gd#L1456)
- Range and vertical-gap gate: [enemies/monster.gd](../../enemies/monster.gd#L1426)
- Chassis-specific range expansion: [enemies/monster.gd](../../enemies/monster.gd#L1437)
- Climbing touching-target LOS override: [enemies/monster.gd](../../enemies/monster.gd#L1450)
- Damage application and cooldown set: [enemies/monster.gd](../../enemies/monster.gd#L960)

### Underfoot equipment attacks
Underfoot equipment attack is conditionally enabled only when the current tracking target is below the monster and a valid nearby damageable equipment candidate is selected.

Evidence:
- Tracking-target-below check: [enemies/monster.gd](../../enemies/monster.gd#L1207)
- Underfoot candidate selector: [enemies/monster.gd](../../enemies/monster.gd#L1211)
- Underfoot attack executor: [enemies/monster.gd](../../enemies/monster.gd#L1254)
- Integration from touching-target selector: [enemies/monster.gd](../../enemies/monster.gd#L1168), [enemies/monster.gd](../../enemies/monster.gd#L1169)

## Test-Derived Behavioral Contracts
- Player climb contract methods are required and mantle helpers are expected removed.
- Monster navigation, climb, targeting, underfoot attack, and chassis-range behavior are test-defined interfaces.

Evidence:
- Player climb method contract checks: [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L118)
- Player mantle-removal checks: [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L120), [tests/test_player_climbing_runtime.gd](../../tests/test_player_climbing_runtime.gd#L21)
- Player climb gate expectation set: [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L35)
- Monster contract method checks: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L71), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L92)
- Monster target-selection expectations: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L430), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L454)
- Underfoot and touching attack expectations: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L659), [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L741)
- Chassis extended range expectation: [tests/test_monster_navigation.gd](../../tests/test_monster_navigation.gd#L892)

## Assumptions and Unknowns
- Tests still assert presence of player helper _can_begin_climb, but this helper is not present in current player runtime script. The implemented gating appears inline in _try_start_climb. This may be intentional refactoring or stale test contract.
  Evidence: [tests/test_player_climbing.gd](../../tests/test_player_climbing.gd#L32), [player/player.gd](../../player/player.gd#L488)
- Combat target collection depends on group membership and take_damage availability, but group assignment sources for all damageable structures are outside this partition.
  Evidence: [enemies/monster.gd](../../enemies/monster.gd#L1313)
