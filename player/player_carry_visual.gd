extends Node
## Arm-only overlay, evaluated after locomotion. Never modifies rest poses or physics.
## Restore before the next animation sample so blends cannot accumulate IK offsets.
var actor: CharacterBody3D
var skeleton: Skeleton3D
var base_rotations: Dictionary = {}
var item: Node3D
var item_hold_transform := Transform3D.IDENTITY
var bounds := AABB()
var right_weight := 0.0
var left_weight := 0.0
var phase := 0.0
var grip_right := Vector3.ZERO
var grip_left := Vector3.ZERO
var hand_frames: Dictionary = {}
var grip_kind := "small"

func _ready() -> void:
	process_physics_priority = 2
	actor = get_parent().get_parent() as CharacterBody3D
	skeleton = get_parent().skeleton
	for side in ["L", "R"]:
		hand_frames[side] = _rest_hand_frame(side)
	set_physics_process(actor != null)

func clear_pose() -> void:
	for bone: int in base_rotations:
		skeleton.set_bone_pose_rotation(bone, base_rotations[bone])
	base_rotations.clear()

func reset() -> void:
	base_rotations.clear()
	right_weight = 0.0
	left_weight = 0.0
	item = null

func _physics_process(delta: float) -> void:
	if actor.is_player_dead: return # Preserve the evaluated pose for ragdoll handoff.
	var held: Node3D = actor.held_item_node
	var driver: Node = get_parent().get_node("Locomotion")
	var blocked: bool = actor.seated_in != null or actor.is_grabbed() or actor.is_placing_equipment() or actor.locomotion_state == actor.LocomotionState.CLIMBING or driver.climb_exit_remaining > 0.0
	if is_instance_valid(held): held.visible = not blocked
	var carrying := is_instance_valid(held) and not blocked
	var large: bool = carrying and bool(actor.inventory.active_item().get("is_large", false))
	right_weight = move_toward(right_weight, 1.0 if carrying else 0.0, delta * 7.0)
	left_weight = move_toward(left_weight, 1.0 if large else 0.0, delta * 7.0)
	# Climbing/grabs immediately own both arms; do not fade over their poses.
	if blocked:
		right_weight = 0.0
		left_weight = 0.0
		return
	if carrying:
		grip_kind = "round" if held is Flashlight else ("large" if large else "small")
		if item != held:
			item = held
			bounds = _held_bounds(item)
			# Held previews already use hold_scale. Cap unusually bulky silhouettes
			# so world-sized barrels/blocks do not intersect the eye or hide both hands.
			var limit := .5 if large else .18
			var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
			var fit := minf(1.0, limit / maxf(longest, .001))
			if large: fit = minf(fit, .4 / maxf(bounds.size.x, .001))
			if fit < 1.0:
				item.scale *= fit
				bounds = _held_bounds(item)
			item_hold_transform = item.transform
		_update_item(delta, large)
	if right_weight > 0.0: _arm("R", grip_right, right_weight)
	if left_weight > 0.0: _arm("L", grip_left, left_weight)
	if carrying and grip_kind == "round":
		_align_flashlight()
		_pose_flashlight_fingers(right_weight)

func _update_item(delta: float, large: bool) -> void:
	if grip_kind == "round": item.transform = item_hold_transform
	# Pitch is limited by reach, independent of free camera look. Both observers
	# and the first-person camera see these same hands and this same prop.
	var pitch: float = clampf(actor.camera.rotation.x, -.45, .45)
	var carry_basis := Basis(Vector3.RIGHT, pitch * .65)
	var speed := Vector2(actor.velocity.x, actor.velocity.z).length() if not actor.in_ui_mode else 0.0
	phase += delta * (8.0 if speed > .1 else 2.0)
	var sway := Vector3(sin(phase * .5) * .006, sin(phase) * .006, 0) * minf(speed, 1.0)
	var center := Vector3(0.0 if large else .04, 1.70 - bounds.size.y * .5 if large else 1.60, -.55 if large else -.48)
	if grip_kind == "round": center = Vector3(.10, 1.69, -.46)
	center += sway + Vector3.DOWN * (1.0 - right_weight) * .16
	center = Vector3(0, 1.45, 0) + carry_basis * (center - Vector3(0, 1.45, 0))
	var marker: Node3D = item.get_parent()
	marker.global_transform = actor.global_transform * Transform3D(carry_basis, center - carry_basis * bounds.get_center())
	# Bounds are in marker space, including the prop's authored rotation/scale.
	# Cup the sides at mid-height instead of reaching over the top edge.
	var right := Vector3(bounds.end.x + .016, bounds.get_center().y, bounds.end.z - .02)
	var left := Vector3(bounds.position.x - .016, right.y, right.z)
	grip_right = marker.to_global(right)
	grip_left = marker.to_global(left)
	for side in ["Right", "Left"]:
		var grip := item.get_node_or_null("Grip" + side) as Node3D
		if grip != null:
			if side == "Right": grip_right = grip.global_position
			else: grip_left = grip.global_position

func _align_flashlight() -> void:
	# Keep the lens aimed forward, and seat the handle against the natural palm.
	# Move the prop, never roll the wrist to force it onto the cylinder.
	var hand := skeleton.find_bone("hand_R")
	var delta := skeleton.global_basis * skeleton.get_bone_global_pose(hand).basis * skeleton.get_bone_global_rest(hand).basis.inverse()
	var frame: Basis = delta * hand_frames["R"]
	var grip := item.get_node("GripRight") as Node3D
	var forward := actor.global_basis * Basis(Vector3.RIGHT, clampf(actor.camera.rotation.x, -.45, .45) * .65) * Vector3.FORWARD
	var outward := (-frame.z - forward * (-frame.z).dot(forward)).normalized()
	var rotation := Basis(outward, forward, outward.cross(forward))
	var fitted := rotation * Basis.from_scale(item_hold_transform.basis.get_scale())
	item.global_transform = Transform3D(fitted, grip_right - fitted * grip.position)

func _pose_flashlight_fingers(weight: float) -> void:
	# Solve each knuckle around the actual barrel cross-section. The index and
	# little finger start at different heights; a shared fist angle clips the tube.
	var body := item.get_node("Body") as MeshInstance3D
	var cylinder := body.mesh as CylinderMesh
	var radius := maxf(cylinder.top_radius, cylinder.bottom_radius) + .012
	for finger in ["index", "middle", "ring", "pinky"]:
		var first := skeleton.find_bone(finger + "_01_R")
		var second := skeleton.find_bone(finger + "_02_R")
		var start := item.to_local(skeleton.global_transform * skeleton.get_bone_global_pose(first).origin)
		var joint := item.to_local(skeleton.global_transform * skeleton.get_bone_global_pose(second).origin)
		var length := start.distance_to(joint)
		var radial := Vector2(start.x, start.z)
		var distance := maxf(radial.length(), .001)
		var along := (distance * distance + radius * radius - length * length) / (2.0 * distance)
		var angle := radial.angle() + acos(clampf(along / radius, -1.0, 1.0))
		var contact := Vector3(cos(angle) * radius, start.y, sin(angle) * radius)
		var tip := Vector3(cos(angle + PI / 3.0) * radius, start.y, sin(angle + PI / 3.0) * radius)
		_finger_world_direction(first, item.global_basis * (contact - start), weight)
		_finger_world_direction(second, item.global_basis * (tip - contact), weight)
	var thumb_axis := item.global_basis.orthonormalized()
	_finger_world_direction(skeleton.find_bone("thumb_01_R"), thumb_axis.y - thumb_axis.x * .25 + thumb_axis.z * .15, weight)
	_finger_world_direction(skeleton.find_bone("thumb_02_R"), thumb_axis.y - thumb_axis.x * .15 + thumb_axis.z * .1, weight)

func _finger_world_direction(bone: int, direction: Vector3, weight: float) -> void:
	var hand := skeleton.find_bone("hand_R")
	var hand_delta := skeleton.get_bone_global_pose(hand).basis * skeleton.get_bone_global_rest(hand).basis.inverse()
	var rest_direction := (skeleton.global_basis * hand_delta).inverse() * direction
	_finger_direction(bone, rest_direction, hand_delta, weight)

func _arm(side: String, contact: Vector3, weight: float) -> void:
	var upper := skeleton.find_bone("upper_arm_" + side)
	var forearm := skeleton.find_bone("forearm_" + side)
	var hand := skeleton.find_bone("hand_" + side)
	var sign_x := 1.0 if side == "R" else -1.0
	# Keep the locomotion wrist local rotation verbatim. The hand
	# follows the forearm naturally; prop markers supply contact positions only.
	var source: Basis = hand_frames[side]
	var rest := skeleton.get_bone_global_rest(hand)
	var middle := skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_" + side)).origin
	var palm_normal := source.y.cross(source.x) * (1.0 if side == "L" else -1.0)
	var palm_center := rest.basis.inverse() * ((middle - rest.origin) * .72 + palm_normal * .014)
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var elbow := skeleton.get_bone_global_pose(forearm).origin
	var old_wrist := skeleton.get_bone_global_pose(hand).origin
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(old_wrist)
	var pole := skeleton.global_basis.inverse() * actor.global_basis * Vector3(sign_x * .45, -1, .15)
	# The inherited hand orientation changes as the elbow bends. Re-evaluate
	# the palm offset with a small fixed solve, without twisting the wrist.
	for iteration in 4:
		var wrist := skeleton.to_local(contact) - skeleton.get_bone_global_pose(hand).basis * palm_center
		var axis := (wrist - shoulder).normalized()
		var distance := clampf(shoulder.distance_to(wrist), absf(a - b) + .001, a + b - .003)
		wrist = shoulder + axis * distance
		var bend := (pole - axis * pole.dot(axis)).normalized()
		var along := (a * a - b * b + distance * distance) / (2.0 * distance)
		var target_elbow := shoulder + axis * along + bend * sqrt(maxf(0, a * a - along * along))
		_aim(upper, forearm, target_elbow, 1.0)
		_aim(forearm, hand, wrist, 1.0)
	for bone in [upper, forearm]:
		skeleton.set_bone_pose_rotation(bone, base_rotations[bone].slerp(skeleton.get_bone_pose_rotation(bone), weight))
	_pose_fingers(side, weight)

func _rest_hand_frame(side: String) -> Basis:
	var wrist := skeleton.get_bone_global_rest(skeleton.find_bone("hand_" + side)).origin
	var middle := skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_" + side)).origin
	var index := skeleton.get_bone_global_rest(skeleton.find_bone("index_01_" + side)).origin
	var pinky := skeleton.get_bone_global_rest(skeleton.find_bone("pinky_01_" + side)).origin
	var forward := (middle - wrist).normalized()
	var radial := index - pinky
	radial = (radial - forward * radial.dot(forward)).normalized()
	return Basis(radial, forward, radial.cross(forward))

func _pose_fingers(side: String, weight: float) -> void:
	if grip_kind == "round": return # Cylinder contact is solved after fitting the prop.
	var frame: Basis = hand_frames[side]
	var palm := frame.y.cross(frame.x) * (1.0 if side == "L" else -1.0)
	var hand := skeleton.find_bone("hand_" + side)
	var hand_delta := skeleton.get_bone_global_pose(hand).basis * skeleton.get_bone_global_rest(hand).basis.inverse()
	# Box support grips stay open, with a small cascade across the four fingers.
	var proximal := 24.0 if grip_kind == "large" else 20.0
	var distal := 32.0 if grip_kind == "large" else 45.0
	var fingers := ["index", "middle", "ring", "pinky"]
	for index in fingers.size():
		var first := skeleton.find_bone(fingers[index] + "_01_" + side)
		var second := skeleton.find_bone(fingers[index] + "_02_" + side)
		var axis := skeleton.get_bone_global_rest(first).basis.y.normalized()
		var flat := (axis - palm * axis.dot(palm)).normalized()
		var first_angle := deg_to_rad(proximal + index * 3.0)
		var tip_angle := first_angle + deg_to_rad(distal + index * 2.0)
		_finger_direction(first, flat * cos(first_angle) + palm * sin(first_angle), hand_delta, weight)
		_finger_direction(second, flat * cos(tip_angle) + palm * sin(tip_angle), hand_delta, weight)
	# A relaxed thumb runs along the fingers/forearm with slight radial opening.
	# Never fold it back across the palm, or rotate the wrist to orient it.
	var thumb_first := (frame.y + frame.x * .25 + palm * .1).normalized()
	var thumb_tip := (frame.y + frame.x * .12 + palm * .18).normalized()
	_finger_direction(skeleton.find_bone("thumb_01_" + side), thumb_first, hand_delta, weight)
	_finger_direction(skeleton.find_bone("thumb_02_" + side), thumb_tip, hand_delta, weight)

func _finger_direction(bone: int, direction: Vector3, hand_delta: Basis, weight: float) -> void:
	var rest := skeleton.get_bone_global_rest(bone).basis
	var rotation := Basis(Quaternion(rest.y.normalized(), direction.normalized())) * rest
	_set_global_rotation(bone, (hand_delta * rotation).get_rotation_quaternion(), weight)

func _save(bone: int) -> void:
	if not base_rotations.has(bone): base_rotations[bone] = skeleton.get_bone_pose_rotation(bone)

func _aim(bone: int, child: int, target: Vector3, weight: float) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var from := (skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var to := (target - pose.origin).normalized()
	_set_global_rotation(bone, Quaternion(from, to) * pose.basis.get_rotation_quaternion(), weight)

func _set_global_rotation(bone: int, rotation: Quaternion, weight: float) -> void:
	_save(bone)
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone)).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, base_rotations[bone].slerp(parent.inverse() * rotation, weight))

func _held_bounds(prop: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var relative: Transform3D = prop.get_parent().global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = relative * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result if not first else AABB(Vector3(-.06, -.06, -.06), Vector3.ONE * .12)
