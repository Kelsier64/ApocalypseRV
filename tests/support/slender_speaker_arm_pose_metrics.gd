extends RefCounted
## Anatomical joint alignment, independent of animation speed or wrist roll.
## A smooth half turn can pass frame-continuity checks while folding the skin.

static func new_metrics() -> Dictionary:
	var metrics := {"samples": 0, "upper_roll_degrees": 0.0, "elbow_plane_degrees": 0.0, "wrist_roll_degrees": 0.0}
	return metrics

static func observe(metrics: Dictionary, skeleton: Skeleton3D) -> void:
	for side in ["L", "R"]:
		var measured := sample(skeleton, side)
		for key in ["upper_roll_degrees", "elbow_plane_degrees", "wrist_roll_degrees"]:
			var value: float = measured[key]
			metrics[key] = maxf(metrics[key], value) if is_finite(value) else INF
	metrics.samples += 1

static func sample(skeleton: Skeleton3D, side: String) -> Dictionary:
	var upper := skeleton.find_bone("upper_arm." + side)
	var lower := skeleton.find_bone("forearm." + side)
	var hand := skeleton.find_bone("hand." + side)
	var middle := skeleton.find_bone("finger_middle_01." + side)
	var index := skeleton.find_bone("finger_index_01." + side)
	var little := skeleton.find_bone("finger_little_01." + side)
	var upper_rest := skeleton.get_bone_global_rest(upper)
	var lower_rest := skeleton.get_bone_global_rest(lower)
	var hand_rest := skeleton.get_bone_global_rest(hand)
	var hand_axis_rest := (skeleton.get_bone_global_rest(middle).origin - hand_rest.origin).normalized()
	var radial_rest := (skeleton.get_bone_global_rest(index).origin - skeleton.get_bone_global_rest(little).origin).slide(hand_axis_rest).normalized()
	var lower_axis_rest := (hand_rest.origin - lower_rest.origin).normalized()
	var upper_axis_rest := (lower_rest.origin - upper_rest.origin).normalized()
	var lower_reference := Basis(Quaternion(hand_axis_rest, lower_axis_rest)) * radial_rest
	var upper_reference := Basis(Quaternion(lower_axis_rest, upper_axis_rest)) * lower_reference
	var upper_pose := skeleton.get_bone_global_pose(upper)
	var lower_pose := skeleton.get_bone_global_pose(lower)
	var hand_pose := skeleton.get_bone_global_pose(hand)
	var upper_axis := (lower_pose.origin - upper_pose.origin).normalized()
	var lower_axis := (hand_pose.origin - lower_pose.origin).normalized()
	var hand_axis := (skeleton.get_bone_global_pose(middle).origin - hand_pose.origin).normalized()
	var hand_radial := (skeleton.get_bone_global_pose(index).origin - skeleton.get_bone_global_pose(little).origin).slide(hand_axis).normalized()
	var lower_radial := (lower_pose.basis * lower_rest.basis.inverse() * lower_reference).slide(lower_axis).normalized()
	var upper_radial := (upper_pose.basis * upper_rest.basis.inverse() * upper_reference).slide(upper_axis).normalized()
	var wrist_reference := (Basis(Quaternion(lower_axis, hand_axis)) * lower_radial).slide(hand_axis).normalized()
	# Remove the clavicle's rotation and the shoulder's swing before measuring
	# axial roll. Keeping forearm and palm frames equal cannot hide this metric.
	var clavicle := skeleton.get_bone_parent(upper)
	var parent_rotation := skeleton.get_bone_global_pose(clavicle).basis * skeleton.get_bone_global_rest(clavicle).basis.inverse()
	var natural_axis := (parent_rotation * upper_axis_rest).normalized()
	var natural_radial := (Basis(Quaternion(natural_axis, upper_axis)) * parent_rotation * upper_reference).slide(upper_axis).normalized()
	# A hinge bends within the rest elbow plane carried by the upper arm.
	# Almost straight elbows do not define a reliable bend-plane direction.
	var flex_degrees := rad_to_deg(upper_axis.angle_to(lower_axis))
	var elbow_plane_degrees := 0.0
	if flex_degrees > 5.0:
		var rest_bend := lower_axis_rest.slide(upper_axis_rest).normalized()
		var expected_bend := (upper_pose.basis * upper_rest.basis.inverse() * rest_bend).slide(upper_axis).normalized()
		var actual_bend := lower_axis.slide(upper_axis).normalized()
		elbow_plane_degrees = rad_to_deg(expected_bend.angle_to(actual_bend))
	return {"upper_roll_degrees": rad_to_deg(natural_radial.angle_to(upper_radial)),
		"elbow_plane_degrees": elbow_plane_degrees,
		"wrist_roll_degrees": rad_to_deg(wrist_reference.angle_to(hand_radial))}
