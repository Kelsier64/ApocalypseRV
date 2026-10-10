extends RefCounted
## Small reach correction over the authored pose. No mirrored meshes or scale.
static func reach(skeleton: Skeleton3D, side: String, world_wrist: Vector3, leg := false) -> bool:
	var upper := skeleton.find_bone(("thigh." if leg else "upper_arm.") + side)
	var lower := skeleton.find_bone(("shin." if leg else "forearm.") + side)
	var hand := skeleton.find_bone(("foot." if leg else "hand.") + side)
	if mini(upper, mini(lower, hand)) < 0: return false
	var upper_pose := skeleton.get_bone_global_pose(upper)
	var lower_pose := skeleton.get_bone_global_pose(lower)
	var hand_pose := skeleton.get_bone_global_pose(hand)
	var palm_basis := hand_pose.basis
	var shoulder := upper_pose.origin
	var wrist := skeleton.to_local(world_wrist)
	var first := shoulder.distance_to(lower_pose.origin)
	var second := lower_pose.origin.distance_to(hand_pose.origin)
	var distance := shoulder.distance_to(wrist)
	if distance > first + second - 0.001: return false
	var axis := (wrist - shoulder).normalized()
	# Move the authored bend plane with the reach axis. Projecting the old
	# elbow directly onto the new axis flips the elbow when that axis crosses
	# the upper arm (especially while reaching a roof-height survivor).
	var authored_axis := (hand_pose.origin - shoulder).normalized()
	var pole := (lower_pose.origin - shoulder).slide(authored_axis).normalized()
	if pole.length_squared() < 0.1:
		pole = upper_pose.basis.x.slide(authored_axis).normalized()
	pole = (Basis(Quaternion(authored_axis, axis)) * pole).slide(axis).normalized()
	var along := (first * first - second * second + distance * distance) / maxf(2.0 * distance, 0.001)
	var elbow := shoulder + axis * along + pole * sqrt(maxf(0.0, first * first - along * along))
	var old_axis := (lower_pose.origin - shoulder).normalized()
	var new_axis := (elbow - shoulder).normalized()
	upper_pose.basis = Basis(Quaternion(old_axis, new_axis)) * upper_pose.basis
	_set_global(skeleton, upper, upper_pose)
	lower_pose = skeleton.get_bone_global_pose(lower)
	hand_pose = skeleton.get_bone_global_pose(hand)
	old_axis = (hand_pose.origin - lower_pose.origin).normalized()
	new_axis = (wrist - lower_pose.origin).normalized()
	lower_pose.basis = Basis(Quaternion(old_axis, new_axis)) * lower_pose.basis
	_set_global(skeleton, lower, lower_pose)
	# Keep the authored palm and thumb orientation while translating the wrist.
	hand_pose.origin = wrist
	hand_pose.basis = palm_basis
	_set_global(skeleton, hand, hand_pose)
	return true

static func follow_palm(skeleton: Skeleton3D, side: String) -> void:
	# Runtime seated alignment may turn a palm around the survivor. Carry that
	# radial frame through both arm segments instead of twisting only the wrist.
	# Roll around each segment's own axis; all joint positions/lengths and the
	# final hand/finger world pose remain unchanged.
	var upper := skeleton.find_bone("upper_arm." + side)
	var lower := skeleton.find_bone("forearm." + side)
	var hand := skeleton.find_bone("hand." + side)
	var index := skeleton.find_bone("finger_index_01." + side)
	var middle := skeleton.find_bone("finger_middle_01." + side)
	var little := skeleton.find_bone("finger_little_01." + side)
	if mini(upper, mini(lower, mini(hand, mini(index, mini(middle, little))))) < 0: return
	var upper_rest := skeleton.get_bone_global_rest(upper)
	var lower_rest := skeleton.get_bone_global_rest(lower)
	var hand_rest := skeleton.get_bone_global_rest(hand)
	var rest_axis := (skeleton.get_bone_global_rest(middle).origin - hand_rest.origin).normalized()
	var rest_radial := (skeleton.get_bone_global_rest(index).origin - skeleton.get_bone_global_rest(little).origin).slide(rest_axis).normalized()
	var rest_lower_axis := (hand_rest.origin - lower_rest.origin).normalized()
	var rest_upper_axis := (lower_rest.origin - upper_rest.origin).normalized()
	var lower_reference := Basis(Quaternion(rest_axis, rest_lower_axis)) * rest_radial
	var upper_reference := Basis(Quaternion(rest_lower_axis, rest_upper_axis)) * lower_reference
	var upper_pose := skeleton.get_bone_global_pose(upper)
	var lower_pose := skeleton.get_bone_global_pose(lower)
	var hand_pose := skeleton.get_bone_global_pose(hand)
	var hand_axis := (skeleton.get_bone_global_pose(middle).origin - hand_pose.origin).normalized()
	var radial := (skeleton.get_bone_global_pose(index).origin - skeleton.get_bone_global_pose(little).origin).slide(hand_axis).normalized()
	var lower_axis := (hand_pose.origin - lower_pose.origin).normalized()
	var upper_axis := (lower_pose.origin - upper_pose.origin).normalized()
	var lower_target := Basis(Quaternion(hand_axis, lower_axis)) * radial
	var upper_target := Basis(Quaternion(lower_axis, upper_axis)) * lower_target
	upper_pose.basis = _radial_rotation(upper_pose.basis, upper_rest.basis.inverse() * upper_reference, upper_target, upper_axis)
	lower_pose.basis = _radial_rotation(lower_pose.basis, lower_rest.basis.inverse() * lower_reference, lower_target, lower_axis)
	_set_global(skeleton, upper, upper_pose)
	_set_global(skeleton, lower, lower_pose)
	_set_global(skeleton, hand, hand_pose)

static func _radial_rotation(posed: Basis, reference: Vector3, target: Vector3, axis: Vector3) -> Basis:
	var current := (posed * reference).slide(axis).normalized()
	var wanted := target.slide(axis).normalized()
	if current.length_squared() < .5 or wanted.length_squared() < .5: return posed
	return Basis(axis, atan2(axis.dot(current.cross(wanted)), current.dot(wanted))) * posed

static func _set_global(skeleton: Skeleton3D, index: int, pose: Transform3D) -> void:
	var parent := skeleton.get_bone_parent(index)
	var parent_pose := skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var local := parent_pose.affine_inverse() * pose
	# Godot 4 bone pose already contains the rest local transform (the GLB
	# translation tracks equal rest origins). Applying rest^-1 here doubles it.
	skeleton.set_bone_pose_position(index, local.origin)
	skeleton.set_bone_pose_rotation(index, local.basis.get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()
