extends "res://enemies/crawler_visual.gd"
## Supine bridge gait on the same skin. The inverted face looks forward and up.

func pose(cycle: float, weight: float) -> void:
	skeleton.reset_bone_poses()
	var hips: Transform3D = skeleton.get_bone_global_rest(bones.pelvis)
	var roll := sin(cycle * TAU) * 0.025 * weight
	hips.basis = Basis(Vector3.BACK, PI + roll) * Basis(Vector3.RIGHT, deg_to_rad(100)) * hips.basis
	hips.origin = Vector3(0, 0.48 + sin(breathing * 2.0) * 0.008, -0.40)
	hips.origin.y += cos(cycle * TAU * 2) * 0.012 * weight
	hips.origin.z += attack_pulse * 0.10
	_set_global(bones.pelvis, hips)
	# Bend back across all three joints; retain the upside-down skull roll.
	# The face ends slightly upward, rather than returning to an upright head.
	for part in ["neck_01", "neck_02", "head"]:
		var index: int = bones[part]
		var neck := skeleton.get_bone_global_pose(index)
		neck.basis = Basis(Vector3.RIGHT, deg_to_rad(28)) * neck.basis
		_set_global(index, neck)
	for side in [-1, 1]:
		# Rolling the torso swaps anatomical left/right in model space.
		var suffix := "_L" if side < 0 else "_R"
		var arm_phase := fposmod(cycle + (0.0 if side > 0 else 0.5), 1.0)
		var leg_phase := fposmod(arm_phase + 0.5, 1.0)
		var hand := Vector3(side * 0.65, 0.035, 0.48) + _step(arm_phase) * weight
		var foot := Vector3(side * 0.61, 0.115, -0.77) + _step(leg_phase) * weight
		_solve_limb("upper_arm" + suffix, "forearm" + suffix, "hand" + suffix, hand, Vector3(side, 0.45, 0.1))
		_solve_limb("thigh" + suffix, "shin" + suffix, "foot" + suffix, foot, Vector3(side * 0.65, 1, -0.15))
		_plant_bridge_hand(side, suffix)
		var ankle: int = bones["foot" + suffix]
		var ankle_pose := skeleton.get_bone_global_pose(ankle)
		ankle_pose.basis = Basis(Vector3.UP, PI + side * 0.2) * skeleton.get_bone_global_rest(ankle).basis
		_set_global(ankle, ankle_pose)

func _plant_bridge_hand(side: int, suffix: String) -> void:
	var hand: int = bones["hand" + suffix]
	var rest := skeleton.get_bone_global_rest(hand)
	var finger := (skeleton.get_bone_global_rest(bones["middle_01" + suffix]).origin - rest.origin).normalized()
	var index := skeleton.get_bone_global_rest(bones["index_01" + suffix]).origin - rest.origin
	var palm := finger.cross(index).normalized() * float(side)
	var local_frame := rest.basis.inverse() * Basis(finger.cross(palm).normalized(), finger, palm)
	var backward := Vector3(side * 0.18, 0, -1).normalized()
	var goal := Basis(backward.cross(Vector3.DOWN).normalized(), backward, Vector3.DOWN)
	var value := skeleton.get_bone_global_pose(hand)
	value.basis = goal * local_frame.inverse()
	_set_global(hand, value)
