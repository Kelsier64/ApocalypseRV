# Knowledge: Equipment Placement and Physics

## 1. Why This Matters
- Equipment placement directly modifies parent hierarchy, collision behavior, and rigid body state.
- Incorrect placement/collision configuration can destabilize RV physics and make the vehicle launch or jitter.
- This workflow is a high-risk area when adding new equipment scenes.

## 2. Trigger Conditions
- Changing `equipment/equipment.gd` placement logic.
- Adding new equipment prefabs derived from `Equipment`.
- Modifying player placement controls or placement ray behavior in `player/player.gd`.

## 3. Canonical Workflow
1. Player holds F for 2 seconds on an `Equipment` target.
2. `start_placement` freezes body, disables collision layers/masks, applies ghost material recursively.
3. Player placement ray computes orientation and offset (surface/upright mode).
4. Left click confirms: equipment reparents, remains frozen static, collision exceptions are added through ancestor chain.
5. Right click cancels: equipment restores original local transform/parent and clears collision exceptions.

## 4. Commands/APIs/Procedures
- Runtime verification:
  - `godot --path . res://world/test_world.tscn`
- Key APIs:
  - `Equipment.start_placement(player)`
  - `Equipment.confirm_placement(new_global_transform, new_parent)`
  - `Equipment.cancel_placement()`
  - `Player.enter_equipment_placement(equip)`
  - `Equipment.get_half_extents()` and `get_bottom_face_correction()` for flush placement math.
- Placement orientation modes:
  - `SURFACE`: bottom face sticks to target surface normal.
  - `UPRIGHT`: bottom stays aligned to world/RV up reference while contacting surface.

## 5. Edge Cases and Failure Patterns
- Missing collision exceptions after reparent: RV can collide with attached equipment and behave explosively.
- Cancelling placement without removing exceptions: future collisions may be incorrectly ignored.
- Equipment without expected collision/mesh shape data falls back to default half-extents and may appear offset.
- Placing while aiming at sky/no collider: placement remains invalid and ghost hides.

## 6. Validation Checklist
- [ ] Hold F enters placement only for `Equipment` and respects 2-second threshold.
- [ ] Ghost material appears during placement and original materials are restored after confirm/cancel.
- [ ] Confirm attach on RV does not cause immediate physics instability.
- [ ] Cancel returns object to original transform/parent and clears exceptions.
- [ ] R key toggles surface/upright orientation behavior as expected.

## 7. Related Modules
- `docs/module/player-and-interaction.md`
- `docs/module/rv-and-equipment.md`

## 8. Source Files Used
- `equipment/equipment.gd`
- `player/player.gd`
- `player/player_interact.gd`
- `equipment/rv_panel.gd`
- `equipment/driver_seat.gd`

## 9. Completeness Notes
- This doc captures the current placement implementation and physics safeguards in code.
- It does not cover editor-only tooling workflows beyond runtime behavior.
