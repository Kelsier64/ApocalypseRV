extends Item
class_name RVLadder
## The origin is the bottom rung's standing level. Local +Z is the approach
## side; the climb lane and landing are measured using actual capsule feet.

const GROUP: StringName = &"rv_ladders"
enum TopExitSide { BACK, FRONT }

@export_range(0.4, 5.0, 0.01) var climb_height: float = 2.21
@export_range(0.4, 0.8, 0.01) var climb_offset: float = 0.55
@export_range(0.5, 2.0, 0.01) var top_exit_distance: float = 1.2
@export var top_exit_side: TopExitSide = TopExitSide.BACK

func _ready() -> void:
	super._ready()
	if presentation_only: return
	add_to_group(GROUP)

func confirm_placement(pose: Transform3D, new_parent: Node3D, support: Node3D = null) -> void:
	# Keep a portable ladder alive while a chunk-owned wall support exits.
	# Item still owns support loss, RV registration, health and placement.
	var actual_support := support if support != null else new_parent
	if RVConnection.resolve(new_parent) == null:
		var container := WorldEntities.get_container(self)
		if container != null: new_parent = container
	super.confirm_placement(pose, new_parent, actual_support)

func get_interaction_prompt(player: Node3D) -> String:
	if player.active_climb_ladder == self and player.ladder_transition == player.LadderTransition.TOP:
		return equipment_name + " | Top of ladder\nRelease movement keys, then use WASD to step off | Space to detach"
	var text := equipment_name + " | W Climb up | S Climb down | Space Detach"
	if not can_climb(): return text + "\nMount the ladder to a wall and repair it first"
	if not player.can_use_hands(2): return text + "\nClimbing requires both arms"
	if player.inventory.is_holding_large_item(): return text + "\nDrop, use, or store your large item first"
	return text + "\nFace the ladder. Press W at the bottom or S at the top."

func can_climb() -> bool:
	return not presentation_only and is_fixed and is_inside_tree() and not is_queued_for_deletion() and enabled \
		and not is_being_placed and not is_destroyed and not support_lost \
		and current_health > 0.0 and freeze and global_basis.y.normalized().dot(Vector3.UP) > 0.85

func climb_point(height: float) -> Vector3:
	return to_global(Vector3(0.0, clampf(height, 0.0, climb_height), climb_offset))

func top_landing_point() -> Vector3:
	var direction := 1.0 if top_exit_side == TopExitSide.FRONT else -1.0
	return to_global(Vector3(0.0, climb_height, climb_offset + direction * top_exit_distance))

## Entry is intentionally restricted to the two ends, not arbitrary RV walls.
func can_enter_from(feet: Vector3, descending: bool) -> bool:
	if not can_climb(): return false
	var local := to_local(feet)
	if absf(local.x) > 0.25: return false
	if descending:
		var landing_z := to_local(top_landing_point()).z
		return absf(local.y - climb_height) <= 0.35 \
			and absf(local.z - landing_z) <= 0.25
	return local.y >= -0.45 and local.y <= 0.3 \
		and local.z >= climb_offset - 0.1 and local.z <= climb_offset + 0.22
