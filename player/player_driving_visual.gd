extends RefCounted
## Seat-space procedural pose on the existing skin, including missing limbs.
## Only presentation bones are changed; vehicle input remains owned by Chassis.
var active := false
var phase := 0.0

func clear(skeleton: Skeleton3D) -> void:
	if not active: return
	skeleton.reset_bone_poses()
	active = false

func update(actor: CharacterBody3D, skeleton: Skeleton3D, carry: Node, delta: float) -> void:
	active = true
	phase += delta
	skeleton.reset_bone_poses()
	var seat: Node3D = actor.seated_in
	var cockpit: Node3D = seat.get_node("CockpitVisual")
	var wheel: Node3D = cockpit.get_node("SteeringTilt/SteeringWheel")
	var rv: Chassis = seat.get_connected_rv()
	var pelvis := skeleton.find_bone("pelvis")
	var root := skeleton.find_bone("root")
	# Cushion top is 0.56 m. The hip joint sits above the clothed seat contact.
	var hip := skeleton.to_local(seat.to_global(Vector3(0, .65, -.015)))
	skeleton.set_bone_pose_position(root, hip - skeleton.get_bone_global_pose(pelvis).origin)
	var spine := skeleton.find_bone("spine_01")
	var base := skeleton.get_bone_global_pose(spine).basis
	var lean := Basis(skeleton.global_basis.inverse() * seat.global_basis.x, -.055 + sin(phase * 1.7) * .004)
	carry._set_global_rotation(spine, (lean * base).get_rotation_quaternion(), 1.0)
	for side in ["L", "R"]:
		_leg(side, seat, skeleton, carry, rv)
	# Grab presentation owns the arms while restrained, preserving the seated legs.
	if actor.is_grabbed(): return
	carry.grip_kind = "small"
	for side in ["L", "R"]:
		if not actor.body_state.has_part(&"left_arm" if side == "L" else &"right_arm"): continue
		# The wheel limits its travel to the existing hand range. Keep each
		# palm at a fixed point on the rim throughout the turn.
		var contact := wheel.to_global(Vector3(-.211 if side == "L" else .211, .018, -.07))
		carry._arm(side, contact, 1.0)

func _leg(side: String, seat: Node3D, skeleton: Skeleton3D, carry: Node, rv: Chassis) -> void:
	var thigh := skeleton.find_bone("thigh_" + side)
	var shin := skeleton.find_bone("shin_" + side)
	var foot := skeleton.find_bone("foot_" + side)
	var hip := skeleton.get_bone_global_pose(thigh).origin
	var knee := skeleton.get_bone_global_pose(shin).origin
	var ankle := skeleton.get_bone_global_pose(foot).origin
	var upper := hip.distance_to(knee)
	var lower := knee.distance_to(ankle)
	var pedal: Node3D = seat.get_node("CockpitVisual/PedalBrake" if side == "L" else "CockpitVisual/PedalThrottle")
	var pressure := (rv.brake_input if side == "L" else rv.throttle_input) if rv != null else 0.0
	# The shoe projects forward of the ankle; flex the foot while pressing.
	var target := skeleton.to_local(pedal.global_position + seat.global_basis * Vector3(0, .10 - pressure * .018, .10))
	var axis := (target - hip).normalized()
	var distance := clampf(hip.distance_to(target), absf(upper - lower) + .001, upper + lower - .003)
	var pole := skeleton.global_basis.inverse() * seat.global_basis * Vector3(0, .5, -1)
	var bend := (pole - axis * pole.dot(axis)).normalized()
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	carry._aim(thigh, shin, hip + axis * along + bend * sqrt(maxf(0, upper * upper - along * along)), 1.0)
	carry._aim(shin, foot, hip + axis * distance, 1.0)
	var rest := skeleton.get_bone_global_rest(foot).basis
	var flex := Basis(skeleton.global_basis.inverse() * seat.global_basis.x, -.12 + pressure * .18)
	carry._set_global_rotation(foot, (flex * rest).get_rotation_quaternion(), 1.0)
