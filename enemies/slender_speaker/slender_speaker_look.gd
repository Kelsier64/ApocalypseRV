extends RefCounted
## Additive presentation on the real neck; vision and audio use its real sockets.
var yaw := 0.0
var pitch := 0.0
var weight := 0.0

func reset() -> void:
	yaw = 0.0
	pitch = 0.0
	weight = 0.0

func update(actor: SlenderSpeaker, point: Vector3, delta: float) -> void:
	if actor.visual == null or not actor.visual.available: return
	var skeleton: Skeleton3D = actor.visual.skeleton
	var index := skeleton.find_bone("neck")
	if index < 0: return
	var focus: Transform3D = actor.visual.bone_world("socket_focus")
	var neck := skeleton.global_transform * skeleton.get_bone_global_pose(index)
	var active := point != Vector3.INF
	var target_yaw := 0.0
	var target_pitch := 0.0
	if active:
		# Aim from the rotation pivot. The offset eye socket moves with the
		# head and otherwise feeds its own motion back into close-range aim.
		var direction := point - neck.origin
		var flat := direction.slide(Vector3.UP)
		if flat.length_squared() > .0001:
			target_yaw = clampf((-actor.global_basis.z).signed_angle_to(flat.normalized(), Vector3.UP), -deg_to_rad(actor.settings.head_yaw_degrees), deg_to_rad(actor.settings.head_yaw_degrees))
			target_pitch = clampf(atan2(direction.y, flat.length()), -deg_to_rad(actor.settings.head_pitch_degrees), deg_to_rad(actor.settings.head_pitch_degrees))
	yaw = move_toward(yaw, target_yaw, deg_to_rad(actor.settings.head_turn_degrees) * delta)
	pitch = move_toward(pitch, target_pitch, deg_to_rad(actor.settings.head_turn_degrees) * .5 * delta)
	weight = move_toward(weight, 1.0 if active else 0.0, delta * 6.0)
	if weight <= 0.0: return
	var forward := focus.basis.y.normalized()
	var desired := actor.global_basis * (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD)
	if not active:
		# Return to the authored attack pose, including its bend, rather than
		# forcing a world-horizontal head during grabs and execution.
		desired = Basis(Vector3.UP, yaw) * forward
		var right := desired.slide(Vector3.UP).normalized().cross(Vector3.UP).normalized()
		desired = Basis(right, pitch) * desired
	var yaw_delta := forward.slide(Vector3.UP).normalized().signed_angle_to(desired.slide(Vector3.UP).normalized(), Vector3.UP)
	var turned := Basis(Vector3.UP, yaw_delta) * forward
	var pitch_delta := atan2(desired.y, desired.slide(Vector3.UP).length()) - atan2(turned.y, turned.slide(Vector3.UP).length())
	var pitch_axis := desired.slide(Vector3.UP).normalized().cross(Vector3.UP).normalized()
	var correction := Basis(pitch_axis, pitch_delta) * Basis(Vector3.UP, yaw_delta)
	correction = Basis(Quaternion.IDENTITY.slerp(correction.get_rotation_quaternion(), weight))
	neck.basis = correction * neck.basis
	actor.ArmIK._set_global(skeleton, index, skeleton.global_transform.affine_inverse() * neck)
	skeleton.force_update_all_bone_transforms()
