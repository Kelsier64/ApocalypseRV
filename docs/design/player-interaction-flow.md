# Player Interaction Flow

## Scope
This document captures interaction behavior driven by the player raycast interaction script, inventory hand-off logic, and prop pickup semantics.

Primary references:
- Interaction loop: [player/player_interact.gd](../../player/player_interact.gd#L8)
- Player inventory and placement entry points: [player/player.gd](../../player/player.gd#L76)
- Prop interaction API: [props/interactable_item.gd](../../props/interactable_item.gd#L16)

## Interaction Detection
The interaction raycast targets objects 3 units in front of the camera each physics tick.

Evidence:
- Raycast processing and target position: [player/player_interact.gd](../../player/player_interact.gd#L8), [player/player_interact.gd](../../player/player_interact.gd#L9)

## E-Key Behavior

### Wheel installation branch
If the player is holding a Wheel and the looked-at object supports install_wheel, holding E accumulates install time and triggers wheel install at 1 second. On successful install, the active inventory item is consumed.

Evidence:
- Wheel branch and hold timing: [player/player_interact.gd](../../player/player_interact.gd#L18), [player/player_interact.gd](../../player/player_interact.gd#L21)
- install_wheel call and item consume: [player/player_interact.gd](../../player/player_interact.gd#L22), [player/player_interact.gd](../../player/player_interact.gd#L23)

### Generic interact-hold branch
When not in wheel-install mode, E key supports two behavior classes:
- Hold >= 1.0s for interact_hold on objects exposing both interact_hold and hold_timer.
- Press/release quick interaction via interact if hold does not complete.

Evidence:
- Hold/quick interaction comment and branch: [player/player_interact.gd](../../player/player_interact.gd#L28), [player/player_interact.gd](../../player/player_interact.gd#L30)
- Hold completion threshold and interact_hold call: [player/player_interact.gd](../../player/player_interact.gd#L33), [player/player_interact.gd](../../player/player_interact.gd#L34)
- Quick interact path: [player/player_interact.gd](../../player/player_interact.gd#L36), [player/player_interact.gd](../../player/player_interact.gd#L37)
- Early release quick pickup path: [player/player_interact.gd](../../player/player_interact.gd#L45), [player/player_interact.gd](../../player/player_interact.gd#L49)

### Debounce behavior
After quick interactions, physics processing is paused and resumed after 0.5 seconds to prevent rapid re-trigger loops.

Evidence:
- Pause, timer, resume sequence: [player/player_interact.gd](../../player/player_interact.gd#L38), [player/player_interact.gd](../../player/player_interact.gd#L39), [player/player_interact.gd](../../player/player_interact.gd#L40)
- Same behavior in release-to-quick branch: [player/player_interact.gd](../../player/player_interact.gd#L50), [player/player_interact.gd](../../player/player_interact.gd#L51), [player/player_interact.gd](../../player/player_interact.gd#L52)

## F-Key Equipment Placement Start
Holding F (while E is not pressed) for 2 seconds starts equipment placement when target object is Equipment and player is not already placing equipment.

Evidence:
- F-key gate and anti-overlap with E: [player/player_interact.gd](../../player/player_interact.gd#L57)
- 2-second hold requirement: [player/player_interact.gd](../../player/player_interact.gd#L61)
- Placement start invocation: [player/player_interact.gd](../../player/player_interact.gd#L62)

## Hold Timer Reset Policy
If interaction is not actively being held, hold_timer is reset on current target to avoid stale accumulation.

Evidence:
- Not-holding reset branch: [player/player_interact.gd](../../player/player_interact.gd#L66), [player/player_interact.gd](../../player/player_interact.gd#L68)

## Prop Pickup and Inventory Hand-off
Prop.interact delegates pickup to player.add_item and only despawns itself on successful add_item.

Evidence:
- Prop interact contract: [props/interactable_item.gd](../../props/interactable_item.gd#L16)
- add_item call and success check: [props/interactable_item.gd](../../props/interactable_item.gd#L22)
- queue_free only after success: [props/interactable_item.gd](../../props/interactable_item.gd#L25)

## Inventory and Placement Integration Points

### Inventory constraints
Player add_item enforces one-large-item-only and max slot count constraints.

Evidence:
- MAX_SLOTS and large-item state: [player/player.gd](../../player/player.gd#L30), [player/player.gd](../../player/player.gd#L32)
- add_item constraints: [player/player.gd](../../player/player.gd#L76), [player/player.gd](../../player/player.gd#L77), [player/player.gd](../../player/player.gd#L80)

### Placement confirmation/cancel flow
When in placement mode, R toggles placement mode, left click confirms placement on resolved parent, and right click cancels placement.

Evidence:
- Placement mode fields: [player/player.gd](../../player/player.gd#L41)
- R toggle: [player/player.gd](../../player/player.gd#L267), [player/player.gd](../../player/player.gd#L269)
- Left-click confirm with can_place gate: [player/player.gd](../../player/player.gd#L273), [player/player.gd](../../player/player.gd#L298)
- Right-click cancel: [player/player.gd](../../player/player.gd#L301), [player/player.gd](../../player/player.gd#L302)

## Assumptions and Unknowns
- Interaction branches rely on duck typing for hold_timer, interact_hold, install_wheel, and start_placement. Interface definitions for those capabilities are not centralized in this partition.
  Evidence: [player/player_interact.gd](../../player/player_interact.gd#L30), [player/player_interact.gd](../../player/player_interact.gd#L22), [player/player_interact.gd](../../player/player_interact.gd#L62)
- Equipment internals are not part of this evidence set, so placement-side validation and collision shaping behavior are documented only from caller perspective.
  Evidence: [player/player.gd](../../player/player.gd#L298)
