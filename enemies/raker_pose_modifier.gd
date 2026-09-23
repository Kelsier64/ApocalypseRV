extends SkeletonModifier3D
## Post-animation face aiming; Skeleton3D restores the input pose each tick.
var actor: Raker
var yaw := 0.0
var pitch := 0.0
var rear_side := 0.0
var tracking_weight := 0.0
var world_positions: Dictionary = {}
const WEIGHTS := [.35, .35, .30]
const BONES := ["neck_01", "neck_02", "head"]

func step_angles(direction: Vector3, delta: float, tracking: bool = true, crouched: bool = false, down_limit: float = 25.0) -> void:
	var target_yaw := 0.0
	var target_pitch := 0.0
	if tracking and direction.length_squared() > .0001:
		var raw := atan2(-direction.x, -direction.z) if Vector2(direction.x, direction.z).length() > .00001 else 0.0
		# Retain the chosen shoulder when a target crosses the exact rear seam.
		if absf(raw) < deg_to_rad(150): rear_side = 0
		elif is_zero_approx(rear_side): rear_side = signf(raw)
		if not is_zero_approx(rear_side): raw = rear_side * absf(raw)
		target_yaw = clampf(raw, -PI / 2, PI / 2)
		target_pitch = clampf(atan2(direction.y, Vector2(direction.x, direction.z).length()), deg_to_rad(-down_limit), deg_to_rad(40 if crouched else 30))
	else: rear_side = 0
	var next := Vector2(yaw, pitch).move_toward(Vector2(target_yaw, target_pitch), PI * delta)
	yaw = next.x
	pitch = clampf(next.y, deg_to_rad(-down_limit), deg_to_rad(40 if crouched else 30))

func _process_modification_with_delta(delta: float) -> void:
	if not is_instance_valid(actor) or not actor.is_node_ready(): return
	var sk := get_skeleton()
	var target: Node3D = actor.target_player
	var tracking := is_instance_valid(target) and WorldEntities.same_world(actor, target) and not actor.is_dead
	var direction := Vector3.ZERO
	if tracking:
		var at: Vector3 = target.camera.global_position if target.get("camera") is Camera3D else target.global_position + Vector3.UP
		if is_instance_valid(target.get("seated_in")): at = target.seated_in.seat_camera.global_position
		var face := sk.global_transform * face_position(sk)
		direction = actor.global_basis.inverse() * (at - face)
	var standing_grab: bool = not actor.crouched and actor.grab.phase in [actor.grab.Phase.REACH, actor.grab.Phase.HOLD, actor.grab.Phase.BITE]
	if tracking and standing_grab:
		var view: Vector3 = target.grab_contact_origin()
		direction = _standing_gaze_direction(sk, view)
	# Reach/hold keep the authored back posture; bite contact is solved below.
	# The neck looks down to a nearby player; locomotion retains its old cap.
	step_angles(direction, delta, tracking, actor.crouched, 65.0 if standing_grab else 25.0)
	tracking_weight = move_toward(tracking_weight, 1.0 if tracking else 0.0, delta * 6.0)
	var biting: bool = is_instance_valid(actor.grab) and actor.grab.phase == actor.grab.Phase.BITE
	var desired := actor.global_basis * Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	_align_face(sk, desired, tracking_weight)
	if biting and is_instance_valid(actor.grab.victim):
		_solve_bite(sk)
	if is_instance_valid(actor.grab) and is_instance_valid(actor.grab.victim):
		var weight := 1.0
		if actor.grab.phase == actor.grab.Phase.REACH: weight = smoothstep(0, actor.grab.REACH_DURATION, actor.grab.elapsed)
		for side in [-1, 1]:
			_solve_arm(sk, side, actor.grab.victim.grab_contact_position(side, actor), weight)
	for name in ["head", "upper_arm_L", "upper_arm_R", "hand_L", "hand_R"]:
		# Cache in skeleton space: physics can move the RV/actor between renders.
		world_positions[name] = sk.get_bone_global_pose(sk.find_bone(name)).origin
	world_positions["mouth"] = mouth_position(sk)
	world_positions["face"] = face_position(sk)
	world_positions["face_forward"] = face_position(sk) + sk.global_basis.inverse()*face_direction(sk)

func _standing_gaze_direction(sk: Skeleton3D, target: Vector3) -> Vector3:
	# Aiming changes the face position around the neck joints. Solve that small
	# parallax first, restore the animation, then apply the normal angular speed
	# limit. Never move a spine bone to compensate for eye contact.
	var original: Array[Quaternion] = []
	for name in BONES: original.append(sk.get_bone_pose_rotation(sk.find_bone(name)))
	var direction := actor.global_basis.inverse() * (target-sk.to_global(face_position(sk)))
	for iteration in 10:
		var y := clampf(atan2(-direction.x,-direction.z),-PI/2,PI/2)
		var p := clampf(atan2(direction.y,Vector2(direction.x,direction.z).length()),deg_to_rad(-65),deg_to_rad(30))
		var desired := Vector3(-sin(y)*cos(p),sin(p),-cos(y)*cos(p))
		_align_face(sk,actor.global_basis*desired,1)
		var next := (actor.global_basis.inverse()*(target-sk.to_global(face_position(sk)))).normalized()
		direction = desired.slerp(next,.5)
	for i in BONES.size(): sk.set_bone_pose_rotation(sk.find_bone(BONES[i]),original[i])
	return direction

func face_direction(sk: Skeleton3D) -> Vector3:
	var head := sk.find_bone("head")
	var local_forward := sk.get_bone_global_rest(head).basis.inverse() * Vector3.BACK
	return (sk.global_basis * sk.get_bone_global_pose(head).basis * local_forward).normalized()

func _align_face(sk: Skeleton3D, desired_world: Vector3, weight: float) -> void:
	# Correct the evaluated face, not an assumed upright animation. Crouching and
	# attacks bend the spine differently; an additive angle cannot cancel that.
	var from := sk.global_basis.inverse() * face_direction(sk)
	var to := sk.global_basis.inverse() * desired_world.normalized()
	var correction := Quaternion(from.normalized(), to.normalized())
	for i in BONES.size():
		var bone := sk.find_bone(BONES[i])
		var pose := sk.get_bone_global_pose(bone)
		pose.basis = Basis(Quaternion.IDENTITY.slerp(correction, WEIGHTS[i] * weight)) * pose.basis
		_set_global(sk, bone, pose)

static func bite_weight(seconds: float) -> float:
	# Brief anticipation, then a fast lunge that stays at contact through damage.
	return smoothstep(.045, .18, seconds)

func mouth_position(sk: Skeleton3D) -> Vector3:
	# v018 native mouth slit in imported rest space, converted to head-local.
	var head := sk.find_bone("head")
	var local := sk.get_bone_global_rest(head).affine_inverse() * Vector3(0, 2.013, .185)
	return sk.get_bone_global_pose(head) * local

func face_position(sk: Skeleton3D) -> Vector3:
	# The visible center between eyes and mouth, not the joint behind the jaw.
	var head := sk.find_bone("head")
	return sk.get_bone_global_pose(head) * (sk.get_bone_global_rest(head).affine_inverse() * Vector3(0,2.055,.19))

func _solve_bite(sk: Skeleton3D) -> void:
	var victim: Node3D = actor.grab.victim
	var view: Camera3D = victim.seated_in.seat_camera if is_instance_valid(victim.seated_in) else victim.camera
	_solve_face_contact(sk, view, bite_weight(actor.grab.elapsed), .055)

func _solve_face_contact(sk: Skeleton3D, view: Camera3D, weight: float, clearance: float) -> void:
	# Lower the torso to the victim's eye height instead of forcing a neck past
	# its downward limit. Aim/position the visible face, so close-up parallax
	# between the head joint and the front of the skull cannot misdirect it.
	var toward := (actor.global_position-view.global_position).slide(Vector3.UP).normalized()
	# Contact the cheek just below eye level so the muzzle stays in front of
	# the near plane; aiming the eye center at point-blank range folds the neck.
	var goal := sk.to_local(view.global_position + toward * clearance - Vector3.UP * .04)
	var contact_facing := -toward
	if actor.grab.victim.is_grabbed():
		# The victim keeps the captured look-up angle. Bring the mouth into that
		# fixed view instead of forcing the camera to chase a lower contact point.
		var view_forward := -view.global_basis.z
		goal = sk.to_local(view.global_position + view_forward * .075)
		var facing := actor.global_basis.inverse() * -view_forward
		var aim_yaw := clampf(atan2(-facing.x,-facing.z), -PI/2, PI/2)
		var aim_pitch := clampf(asin(clampf(facing.y,-1,1)), deg_to_rad(-25 if actor.crouched else -65), deg_to_rad(40 if actor.crouched else 30))
		contact_facing = actor.global_basis * Vector3(-sin(aim_yaw)*cos(aim_pitch),sin(aim_pitch),-cos(aim_yaw)*cos(aim_pitch))
	var target := mouth_position(sk).lerp(goal, weight)
	var bite_facing := face_direction(sk).slerp(contact_facing, weight).normalized()
	var chain := ["spine_01", "spine_02", "spine_03"]
	var original: Array[Quaternion] = []
	for name in chain: original.append(sk.get_bone_pose_rotation(sk.find_bone(name)))
	for iteration in 24:
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
			var limit := deg_to_rad(55)
			if angle > limit:
				sk.set_bone_pose_rotation(bone, original[i].slerp(rotation, limit / angle))
		# Use the approach direction at contact: chasing a point centimeters from
		# the eyes creates an unstable near-field aim/position feedback loop.
		_align_face(sk, bite_facing, 1.0)

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
	# Cup both sides of the head with fingers wrapping toward its back.
	_orient_grip(sk, side, fore, hand, weight)

func _hand_frame(sk: Skeleton3D, side: int, rest: bool) -> Basis:
	var suffix := "_R" if side > 0 else "_L"
	var hand := sk.find_bone("hand"+suffix)
	var middle := sk.find_bone("middle_01"+suffix)
	var index := sk.find_bone("index_01"+suffix)
	var h := sk.get_bone_global_rest(hand) if rest else sk.get_bone_global_pose(hand)
	var m := sk.get_bone_global_rest(middle) if rest else sk.get_bone_global_pose(middle)
	var ix := sk.get_bone_global_rest(index) if rest else sk.get_bone_global_pose(index)
	var fingers := (m.origin-h.origin).normalized()
	# The old sign described the BACK of this mesh's hands, not their palms.
	var palm := fingers.cross(ix.origin-m.origin).normalized()*float(-side)
	return Basis(fingers.cross(palm).normalized(), fingers, palm)

func _orient_grip(sk: Skeleton3D, side: int, fore: int, hand: int, weight: float) -> void:
	var palm := sk.global_basis.inverse() * (-actor.global_basis.x * float(side))
	var fingers := sk.global_basis.inverse() * (Vector3.UP*.8-actor.global_basis.z*.6).normalized()
	var fore_pose := sk.get_bone_global_pose(fore)
	var axis := (sk.get_bone_global_pose(hand).origin-fore_pose.origin).normalized()
	var current := _hand_frame(sk,side,false).z.slide(axis).normalized()
	var desired := palm.slide(axis).normalized()
	if current.length_squared() > .001 and desired.length_squared() > .001:
		var twist := current.signed_angle_to(desired,axis)
		fore_pose.basis = Basis(axis,twist*.65*weight)*fore_pose.basis
		_set_global(sk,fore,fore_pose)
	var rest_frame := sk.get_bone_global_rest(hand).basis.inverse()*_hand_frame(sk,side,true)
	var goal := Basis(fingers.cross(palm).normalized(),fingers,palm)*rest_frame.inverse()
	var pose := sk.get_bone_global_pose(hand)
	pose.basis = Basis(pose.basis.get_rotation_quaternion().slerp(goal.get_rotation_quaternion(),weight))
	_set_global(sk,hand,pose)
	# Flex in each finger's anatomical palm plane, independent of wrist roll.
	# A world-down target can hyperextend a joint during partial grip blending.
	var suffix := "_R" if side > 0 else "_L"
	var actual_palm := _hand_frame(sk,side,false).z
	for finger in ["index", "middle", "ring", "pinky"]:
		var base := sk.find_bone(finger+"_01"+suffix)
		var joint := sk.find_bone(finger+"_02"+suffix)
		var digit := sk.get_bone_global_pose(joint)
		var proximal := (digit.origin-sk.get_bone_global_pose(base).origin).normalized()
		var inward := actual_palm.slide(proximal).normalized()
		var tip_direction := proximal*cos(PI/4)+inward*sin(PI/4)
		var curl := Quaternion(digit.basis.y.normalized(), tip_direction)
		digit.basis = Basis(Quaternion.IDENTITY.slerp(curl, weight))*digit.basis
		_set_global(sk,joint,digit)
