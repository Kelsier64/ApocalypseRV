extends SkeletonModifier3D
## Post-animation additive rotations; Skeleton3D restores the input pose each tick.
var actor: Raker
var yaw := 0.0
var pitch := 0.0
var rear_side := 0.0
var world_positions: Dictionary = {}
const WEIGHTS := [.35, .35, .30]
const BONES := ["neck_01", "neck_02", "head"]

func step_angles(direction: Vector3, delta: float, tracking: bool = true, crouched: bool = false) -> void:
	var target_yaw := 0.0
	var target_pitch := 0.0
	if tracking and direction.length_squared() > .0001:
		var raw := atan2(-direction.x, -direction.z) if Vector2(direction.x, direction.z).length() > .00001 else 0.0
		# Retain the chosen shoulder when a target crosses the exact rear seam.
		if absf(raw) < deg_to_rad(150): rear_side = 0
		elif is_zero_approx(rear_side): rear_side = signf(raw)
		if not is_zero_approx(rear_side): raw = rear_side * absf(raw)
		target_yaw = clampf(raw, -PI / 2, PI / 2)
		target_pitch = clampf(atan2(direction.y, Vector2(direction.x, direction.z).length()), deg_to_rad(-25), deg_to_rad(40 if crouched else 30))
	else: rear_side = 0
	var next := Vector2(yaw, pitch).move_toward(Vector2(target_yaw, target_pitch), PI * delta)
	yaw = next.x
	pitch = clampf(next.y, deg_to_rad(-25), deg_to_rad(40 if crouched else 30))

func _process_modification_with_delta(delta: float) -> void:
	if not is_instance_valid(actor) or not actor.is_node_ready(): return
	var sk := get_skeleton()
	var target: Node3D = actor.target_player
	var tracking := is_instance_valid(target) and WorldEntities.same_world(actor, target) and not actor.is_dead
	var direction := Vector3.ZERO
	if tracking:
		var at: Vector3 = target.camera.global_position if target.get("camera") is Camera3D else target.global_position + Vector3.UP
		if is_instance_valid(target.get("seated_in")): at = target.seated_in.seat_camera.global_position
		var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head")).origin
		direction = actor.global_basis.inverse() * (at - head)
	step_angles(direction, delta, tracking, actor.crouched)
	var biting: bool = is_instance_valid(actor.grab) and actor.grab.phase == actor.grab.Phase.BITE
	var neck_weight := 1.0
	if is_instance_valid(actor.grab):
		if actor.grab.phase == actor.grab.Phase.HOLD: neck_weight = clampf((2.0 - actor.grab.elapsed) / .15, 0, 1)
		elif actor.grab.phase == actor.grab.Phase.RELEASE: neck_weight = clampf(actor.grab.elapsed / .15, 0, 1)
	if biting and is_instance_valid(actor.grab.victim):
		_solve_bite(sk)
	else:
		for i in BONES.size():
			var bone := sk.find_bone(BONES[i])
			var pose := sk.get_bone_global_pose(bone)
			var axis_y := sk.global_basis.inverse() * actor.global_basis.y
			var axis_x := sk.global_basis.inverse() * actor.global_basis.x
			pose.basis = Basis(Quaternion(axis_y.normalized(), yaw * WEIGHTS[i] * neck_weight) * Quaternion(axis_x.normalized(), pitch * WEIGHTS[i] * neck_weight)) * pose.basis
			_set_global(sk, bone, pose)
	if is_instance_valid(actor.grab) and is_instance_valid(actor.grab.victim):
		var weight := 1.0
		if actor.grab.phase == actor.grab.Phase.REACH: weight = smoothstep(0, .6, actor.grab.elapsed)
		for side in [-1, 1]:
			_solve_arm(sk, side, actor.grab.victim.grab_contact_position(side, actor), weight)
	for name in ["head", "upper_arm_L", "upper_arm_R", "hand_L", "hand_R"]:
		# Cache in skeleton space: physics can move the RV/actor between renders.
		world_positions[name] = sk.get_bone_global_pose(sk.find_bone(name)).origin
	world_positions["mouth"] = mouth_position(sk)

static func bite_weight(seconds: float) -> float:
	return smoothstep(.08, .32, seconds) * (1.0 - smoothstep(.40, .65, seconds))

func mouth_position(sk: Skeleton3D) -> Vector3:
	# v017 mouth center in the imported model's rest space, converted to head-local.
	var head := sk.find_bone("head")
	var local := sk.get_bone_global_rest(head).affine_inverse() * Vector3(0, 2.013, .195)
	return sk.get_bone_global_pose(head) * local

func _solve_bite(sk: Skeleton3D) -> void:
	var victim: Node3D = actor.grab.victim
	var view: Camera3D = victim.seated_in.seat_camera if is_instance_valid(victim.seated_in) else victim.camera
	var weight := bite_weight(actor.grab.elapsed)
	# Stop just in front of the face: camera never moves through the creature.
	var toward: Vector3 = (actor.grab_face_position() - view.global_position).normalized()
	var goal := sk.to_local(view.global_position + toward * .075)
	var target := mouth_position(sk).lerp(goal, weight)
	var chain := ["spine_01", "spine_02", "spine_03"]
	var original: Array[Quaternion] = []
	for name in chain: original.append(sk.get_bone_pose_rotation(sk.find_bone(name)))
	# Bend the torso, not bone translations; feet, root and neck lengths stay fixed.
	for iteration in 16:
		for i in range(chain.size() - 1, -1, -1):
			var bone := sk.find_bone(chain[i])
			var pose := sk.get_bone_global_pose(bone)
			var from := mouth_position(sk) - pose.origin
			var to := target - pose.origin
			if minf(from.length_squared(), to.length_squared()) < .00001: continue
			pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
			_set_global(sk, bone, pose)
			var rotation := sk.get_bone_pose_rotation(bone)
			var angle := original[i].angle_to(rotation)
			if angle > deg_to_rad(55):
				sk.set_bone_pose_rotation(bone, original[i].slerp(rotation, deg_to_rad(55) / angle))

func _set_global(sk: Skeleton3D, bone: int, pose: Transform3D) -> void:
	var parent := sk.get_bone_parent(bone)
	var local := sk.get_bone_global_pose(parent).affine_inverse() * pose if parent >= 0 else pose
	# Preserve translation/scale: only the rotation is authorized to change.
	sk.set_bone_pose_rotation(bone, local.basis.orthonormalized().get_rotation_quaternion())

func _aim(sk: Skeleton3D, bone: int, child: int, point: Vector3) -> void:
	var pose := sk.get_bone_global_pose(bone)
	var from := sk.get_bone_global_pose(child).origin - pose.origin
	var to := point - pose.origin
	if from.length_squared() < .00001 or to.length_squared() < .00001: return
	pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	_set_global(sk, bone, pose)

func _solve_arm(sk: Skeleton3D, side: int, contact: Vector3, weight: float) -> void:
	var suffix := "_R" if side > 0 else "_L"
	var upper := sk.find_bone("upper_arm" + suffix)
	var fore := sk.find_bone("forearm" + suffix)
	var hand := sk.find_bone("hand" + suffix)
	var shoulder := sk.get_bone_global_pose(upper).origin
	var elbow := sk.get_bone_global_pose(fore).origin
	var wrist := sk.get_bone_global_pose(hand).origin
	var target := wrist.lerp(sk.to_local(contact), weight)
	var length_a := shoulder.distance_to(elbow)
	var length_b := elbow.distance_to(wrist)
	var direction := (target - shoulder).normalized()
	var distance := clampf(target.distance_to(shoulder), .02, length_a + length_b - .001)
	var along := (length_a * length_a - length_b * length_b + distance * distance) / (2 * distance)
	var height := sqrt(maxf(0, length_a * length_a - along * along))
	var up := is_instance_valid(actor.grab.victim) and is_instance_valid(actor.grab.victim.seated_in)
	var down := sk.global_basis.inverse() * ((Vector3.UP if up else Vector3.DOWN) + actor.global_basis.x * float(side) * .25)
	var bend := down.slide(direction).normalized()
	_aim(sk, upper, fore, shoulder + direction * along + bend * height)
	_aim(sk, fore, hand, shoulder + direction * distance)
	# Retain the authored local wrist rotation as the forearm changes direction.
