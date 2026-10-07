extends SkeletonModifier3D
## Small post-animation, two-bone terrain correction; never moves gameplay root.
var actor: BarrelMan
var landing_compression := 0.0

func _process_modification_with_delta(_delta: float) -> void:
	if not is_instance_valid(actor) or not actor.is_node_ready() or actor.phase != BarrelMan.Phase.CHASE or not actor.is_on_floor(): return
	var sk := get_skeleton()
	for suffix in ["L", "R"]:
		var upper := sk.find_bone("thigh_" + suffix)
		var lower := sk.find_bone("shin_" + suffix)
		var foot := sk.find_bone("foot_" + suffix)
		if upper < 0 or lower < 0 or foot < 0: continue
		var hip := sk.get_bone_global_pose(upper)
		var knee := sk.get_bone_global_pose(lower)
		var ankle := sk.get_bone_global_pose(foot)
		var world := sk.to_global(ankle.origin)
		# Swing feet are intentionally airborne and should not be pulled down.
		if world.y - actor.global_position.y > .22: continue
		var query := PhysicsRayQueryParameters3D.create(world + Vector3.UP * .18, world - Vector3.UP * .30, 1, [actor.get_rid()])
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.normal.y < .65: continue
		# Preserve the authored heel/toe roll. The ankle intentionally rises
		# during push-off; snapping it to a fixed 11.5 cm would bury the toes.
		# Only terrain height relative to the grounded actor and the additional
		# landing compression require correction.
		var correction := clampf(float(hit.position.y) - actor.global_position.y + landing_compression, -.08, .10)
		if absf(correction) < .002: continue
		var target := sk.to_local(world + Vector3.UP * correction)
		var length_a := hip.origin.distance_to(knee.origin)
		var length_b := knee.origin.distance_to(ankle.origin)
		var direction := (target - hip.origin).normalized()
		var distance := clampf(hip.origin.distance_to(target), absf(length_a - length_b) + .001, length_a + length_b - .001)
		target = hip.origin + direction * distance
		var along := (length_a * length_a - length_b * length_b + distance * distance) / (2.0 * distance)
		var bend := (knee.origin - hip.origin).slide(direction).normalized()
		if bend.is_zero_approx(): continue
		var next_knee := hip.origin + direction * along + bend * sqrt(maxf(0.0, length_a * length_a - along * along))
		hip.basis = Basis(Quaternion((knee.origin - hip.origin).normalized(), (next_knee - hip.origin).normalized())) * hip.basis
		knee.basis = Basis(Quaternion((ankle.origin - knee.origin).normalized(), (target - next_knee).normalized())) * knee.basis
		knee.origin = next_knee
		ankle.origin = target
		sk.set_bone_global_pose(upper, hip)
		sk.set_bone_global_pose(lower, knee)
		sk.set_bone_global_pose(foot, ankle)
