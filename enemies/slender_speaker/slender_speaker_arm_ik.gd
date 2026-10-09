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
	var pole := (lower_pose.origin - shoulder).slide(axis).normalized()
	if pole.length_squared() < 0.1: pole = Vector3.RIGHT.slide(axis).normalized()
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

static func _set_global(skeleton: Skeleton3D, index: int, pose: Transform3D) -> void:
	var parent := skeleton.get_bone_parent(index)
	var parent_pose := skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var local := parent_pose.affine_inverse() * pose
	# Godot 4 bone pose already contains the rest local transform (the GLB
	# translation tracks equal rest origins). Applying rest^-1 here doubles it.
	skeleton.set_bone_pose_position(index, local.origin)
	skeleton.set_bone_pose_rotation(index, local.basis.get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()
