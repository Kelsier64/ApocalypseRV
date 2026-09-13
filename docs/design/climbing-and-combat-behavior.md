# Climbing and Combat Behavior

## Movement states

Both actors use NORMAL and CLIMBING locomotion. The player enters climbing by holding forward against an RV wall with valid height, surface normal, and headroom. Monsters enter from chase. Back or a newly pressed jump detaches the player; holding jump from the approach does not repeatedly cancel climbing.

The capsule stays enabled throughout climbing. All climbing and vehicle-follow movement uses body sweeps, so an overhead obstacle cannot be crossed simply because the wall ray remains valid.

## Moving vehicle attachment

`ClimbMath.attachment_delta` carries the actor's point through the RV's complete transform, including turns. Wall normals and actor heading rotate with the vehicle. A frame displacement over 1.5 metres aborts attachment instead of silently losing the excess displacement. High angular speed and invalid RV references also terminate climbing.

Wall probes are refreshed after compensation. Brief contact loss is tolerated while reaching the upper edge. `ClimbMath.try_roof_transfer` requires a real RV roof below the destination and a clear full-capsule sweep before stepping inward. A missing wall alone does not authorize moving through the vehicle.

Detachment inherits the vehicle's point velocity. The player keeps its horizontal carrier momentum while airborne, with movement input added separately.

## Standing on the RV

`RVSupport` tracks the exact supporting collider and its owning RV. This is necessary because mounted panels are frozen child bodies and do not report the chassis's platform velocity. Player and monster disable built-in floor-platform carry to avoid applying motion twice, then explicitly follow RV supports.

Support is reacquired from actual floor collisions after movement. Deleted, detached, or teleported supports are released. Ordinary world floors need no carry; moving non-RV platforms are outside this prototype's supported platform contract.

Seated players retain their physics callback to update their world position from the driver's seat. Monster perception therefore follows the driver instead of pursuing the old boarding location. Seat entry clears climbing/support state; seat exit inherits physical vehicle velocity.

## Monster combat

Ground targeting normally prefers players, then structures. While climbing, only nearby visible structures qualify. A monster with valid wall contact can continue climbing and damaging the RV after its target leaves.

Contact attacks require line of sight. Touching the chassis does not count as touching every equipment descendant, and hitting an ancestor with a visibility ray does not expose an interior target through the wall.

When a player is below the monster and the downward probe hits damageable equipment, that panel remains the attack target during cooldown. The direct probe supplies range and obstruction evidence; distance to a large panel's centre must not reject a valid foot contact. Destruction removes the support and the monster falls. Underfoot attacks exclude the chassis and players.

## Verification

Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1`.

`tests/test_moving_rv_climbing.gd` uses the production player, zombie, complete RV, panels, and driver's seat. It checks moving-wall ascent, roof transfer, translation and steering, physics-driven VehicleBody support, release velocity, overhead collision, occluded equipment, driver tracking, roof destruction, and falling after support removal.

For interactive inspection:

```powershell
godot --path . res://tests/rv_climb_playground.tscn
godot --path . res://tests/rv_climb_playground.tscn -- --replay
```

F2 toggles deterministic vehicle motion; F3 starts automatic player climbing; F4 switches camera; F5 seats the player to exercise roof attacks; R resets. WASD and Space use production player controls in the first-person view. The playground uses scripted RV translation/turning for reproducibility; wheel-driven handling, severe rollovers, and dense crowds still need gameplay testing.
