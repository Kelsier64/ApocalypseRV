extends Node
## Transient physical pose and death camera; Player retains health/mode ownership.
## Imported rest frames stay unchanged; local inertia/damping supports 60 Hz.
const BODY_LAYER := 128
const RESPAWN_DELAY := 2.0
const HEAD_CENTER := Vector3(0, 1.475, -0.042)
var player: CharacterBody3D
var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var bodies: Dictionary = {}
var links: Array[Dictionary] = []
var active := false
var remaining := 0.0
var camera_rest := Transform3D.IDENTITY
var camera_basis := Basis.IDENTITY
var eye_offset := Vector3.ZERO
var camera_shape := SphereShape3D.new()
var allowed_bones: Array[String] = []
var presence_signature := ""
var detached_head: Node3D
var following_detached_head := false
var last_head_anchor := Vector3.ZERO

func _ready() -> void:
	player = get_parent()
	skeleton = player.get_node("Visuals").skeleton
	camera_shape.radius = 0.06
	set_physics_process(false)

func follow_detached_head(head: Node3D, view: Transform3D) -> void:
	# Capture before grab cleanup restores the eye or seat exit moves the body.
	detached_head = head
	following_detached_head = true
	last_head_anchor = head.camera_anchor_position()
	eye_offset = view.origin - last_head_anchor
	camera_basis = view.basis.orthonormalized()
	head.set_camera_hidden(true)
	# Held heads update their mouth attachment before the death camera follows.
	process_physics_priority = 100

func start(inherited_velocity: Vector3) -> void:
	if active: return
	var signature := str(player.body_state.capture())
	if simulator != null and signature != presence_signature:
		simulator.free()
		simulator = null
		bodies.clear()
		links.clear()
	presence_signature = signature
	allowed_bones.assign(["pelvis", "spine_01", "spine_02"])
	if player.body_state.has_part(&"head"): allowed_bones.append("head")
	for side in ["L", "R"]:
		var prefix := "left" if side == "L" else "right"
		if player.body_state.has_part(prefix + "_arm"): allowed_bones.append_array(["upper_arm_" + side, "forearm_" + side])
		if player.body_state.has_part(prefix + "_leg"): allowed_bones.append_array(["thigh_" + side, "shin_" + side, "foot_" + side])
	player.get_node("Visuals/Locomotion").suspend()
	if simulator == null:
		# Build joint reference frames from the immutable bind pose, not the
		# arbitrary animation frame at the first death. Restore before simulating.
		var visible_pose: Array[Transform3D] = []
		for bone in skeleton.get_bone_count(): visible_pose.append(skeleton.get_bone_pose(bone))
		skeleton.reset_bone_poses()
		skeleton.force_update_all_bone_transforms()
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
		simulator = PhysicalBoneSimulator3D.new()
		simulator.name = "PhysicalBoneSimulator"
		skeleton.add_child(simulator)
		build_bodies()
		for bone in skeleton.get_bone_count(): skeleton.set_bone_pose(bone, visible_pose[bone])
		skeleton.force_update_all_bone_transforms()
	active = true
	player.get_node("Visuals").set_death_view(true)
	remaining = RESPAWN_DELAY
	camera_rest = player.camera.transform
	# Keep the current climbed eye position for the physical handoff below,
	# but recovery must restore the standing eye, without the approach offset.
	camera_rest.origin = player.get_node("Visuals/Locomotion").camera_rest_position
	if not following_detached_head:
		camera_basis = player.camera.global_basis.orthonormalized()
	skeleton.force_update_all_bone_transforms()
	# Explicit placement is also necessary after a respawn or World3D transfer.
	for body: PhysicalBone3D in bodies.values():
		body.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(body.get_bone_id()) * body.body_offset
		body.collision_layer = BODY_LAYER
		body.collision_mask = 1 | BODY_LAYER
	if not following_detached_head:
		eye_offset = player.camera.global_position - bodies.get("head", bodies["spine_02"]).global_position
	simulator.active = true
	simulator.physical_bones_start_simulation()
	for body: PhysicalBone3D in bodies.values():
		body.linear_velocity = inherited_velocity
		body.angular_velocity = Vector3.ZERO
	# A small forward loss of balance lets a motionless neutral pose collapse.
	bodies["spine_02"].apply_central_impulse(-player.global_basis.z * 3.0)
	if following_detached_head: _update_camera()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not active: return
	_update_camera()
	remaining -= delta
	if remaining <= 0.0:
		remaining = 0.25 # Retry only if the standing volume is still obstructed.
		player._respawn.call_deferred()

func _update_camera() -> void:
	# Translation follows the physical head; its tumbling never rotates the view.
	var origin: Vector3 = bodies.get("head", bodies["spine_02"]).global_position
	if following_detached_head:
		if is_instance_valid(detached_head) and not detached_head.is_queued_for_deletion() and WorldEntities.same_world(player, detached_head):
			last_head_anchor = detached_head.camera_anchor_position()
		else:
			# A culled or transferred cosmetic head must not teleport the dying
			# player's view back to a distant corpse. Hold the last valid anchor.
			if is_instance_valid(detached_head): detached_head.set_camera_hidden(false)
			detached_head = null
		origin = last_head_anchor
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = camera_shape
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.motion = eye_offset
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var fraction := player.get_world_3d().direct_space_state.cast_motion(query)[0]
	player.camera.global_transform = Transform3D(camera_basis, origin + eye_offset * maxf(0.0, fraction - 0.02))

func recovery_position() -> Vector3:
	var center: Vector3 = bodies["pelvis"].global_position
	var candidates: Array[Vector3] = [center]
	for radius in [0.6, 1.2, 2.0, 3.0]:
		for i in 12:
			candidates.append(center + Vector3(cos(i * TAU / 12.0), 0, sin(i * TAU / 12.0)) * radius)
	var collider: CollisionShape3D = player.body_collision_shape
	var capsule: CapsuleShape3D = player.standing_collision_shape
	var upright: Transform3D = player.standing_collision_transform
	var sole_y := upright.origin.y - capsule.height * 0.5
	var space := player.get_world_3d().direct_space_state
	for candidate in candidates:
		# Search below the body; a low ceiling must not become a roof teleport.
		var ray := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 0.4, candidate - Vector3.UP * 3.0, player.collision_mask, [player.get_rid()])
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.dot(Vector3.UP) < 0.7: continue
		var standing: Vector3 = hit.position + Vector3.UP * (0.035 - sole_y)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(player.global_basis, standing) * upright
		query.collision_mask = player.collision_mask
		query.exclude = [player.get_rid()]
		if space.intersect_shape(query, 1).is_empty(): return standing
	return Vector3.INF

func stop() -> void:
	if is_instance_valid(detached_head): detached_head.set_camera_hidden(false)
	detached_head = null
	following_detached_head = false
	process_physics_priority = 0
	if not active: return
	set_physics_process(false)
	simulator.physical_bones_stop_simulation()
	simulator.active = false
	for body: PhysicalBone3D in bodies.values():
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.collision_layer = 0
		body.collision_mask = 0
	skeleton.reset_bone_poses()
	player.camera.transform = camera_rest
	player.get_node("Visuals/Carry").reset()
	player.get_node("Visuals").set_death_view(false)
	active = false
	remaining = 0.0

func _exit_tree() -> void:
	if is_instance_valid(detached_head): detached_head.set_camera_hidden(false)

func build_bodies() -> void:
	add_box("pelvis", Vector3(0, 0.875, -0.035), Vector3(0.27, 0.18, 0.20), 12.0)
	add_box("spine_01", Vector3(0, 1.055, -0.045), Vector3(0.25, 0.14, 0.18), 8.0, 20.0, 15.0)
	add_box("spine_02", Vector3(0, 1.235, -0.040), Vector3(0.33, 0.20, 0.20), 14.0, 25.0, 20.0)
	add_capsule("head", HEAD_CENTER, Vector3.UP, 0.105, 0.25, 4.5, 35.0, 45.0)
	for side: String in ["L", "R"]:
		var upper := "upper_arm_" + side
		var forearm := "forearm_" + side
		var thigh := "thigh_" + side
		var shin := "shin_" + side
		var foot := "foot_" + side
		add_segment(upper, forearm, 0.057, 2.0, 75.0, 45.0)
		add_segment(forearm, "hand_" + side, 0.045, 1.5, 0.0, 0.0, 0.105)
		add_segment(thigh, shin, 0.078, 6.0, 80.0, 30.0)
		add_segment(shin, foot, 0.055, 3.5, 0.0, 0.0)
		var x := rest(foot).origin.x
		add_box(foot, Vector3(x, 0.074, 0.035), Vector3(0.13, 0.135, 0.29), 2.5, 40.0, 20.0)
	# The engine connects a bone to its nearest physical ancestor, skipping
	# clavicles/neck without changing the 41-bone imported skeleton.
	for key: String in bodies:
		var child: PhysicalBone3D = bodies[key]
		var parent_index := skeleton.get_bone_parent(child.get_bone_id())
		while parent_index >= 0 and not bodies.has(String(skeleton.get_bone_name(parent_index))):
			parent_index = skeleton.get_bone_parent(parent_index)
		if parent_index < 0:
			continue
		var parent: PhysicalBone3D = bodies[String(skeleton.get_bone_name(parent_index))]
		child.add_collision_exception_with(parent)
		parent.add_collision_exception_with(child)
		var joint_world := child.global_transform * child.joint_offset
		links.append({"child": child, "parent": parent, "parent_frame": parent.global_transform.affine_inverse() * joint_world})
	# Near neighbours overlap by design at hips/shoulders; distant limbs still collide.
	for link: Dictionary in links:
		for ancestor: Dictionary in links:
			if link.parent == ancestor.child:
				link.child.add_collision_exception_with(ancestor.parent)
				ancestor.parent.add_collision_exception_with(link.child)
	for pair in [["thigh_L", "thigh_R"], ["spine_01", "thigh_L"], ["spine_01", "thigh_R"], ["spine_01", "upper_arm_L"], ["spine_01", "upper_arm_R"]]:
		if not bodies.has(pair[0]) or not bodies.has(pair[1]): continue
		bodies[pair[0]].add_collision_exception_with(bodies[pair[1]])
		bodies[pair[1]].add_collision_exception_with(bodies[pair[0]])
	# Isolated control capsule never participates in ragdoll collisions.
	simulator.physical_bones_add_collision_exception(player.get_rid())

func rest(bone_name: String) -> Transform3D:
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone_name))

func add_segment(bone_name: String, end_name: String, radius: float, mass_kg: float, swing: float, twist: float, extension := 0.0) -> void:
	var start := rest(bone_name).origin
	var end := rest(end_name).origin
	var direction := (end - start).normalized()
	end += direction * extension
	add_capsule(bone_name, (start + end) * 0.5, direction, radius, start.distance_to(end), mass_kg, swing, twist)

func add_box(bone_name: String, center: Vector3, size: Vector3, mass_kg: float, swing := 0.0, twist := 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	add_body(bone_name, Transform3D(Basis.IDENTITY, center), shape, mass_kg, swing, twist)

func add_capsule(bone_name: String, center: Vector3, direction: Vector3, radius: float, height: float, mass_kg: float, swing: float, twist: float) -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, 2.0 * radius)
	var z := Vector3.RIGHT.cross(direction).normalized()
	var x := direction.cross(z).normalized()
	add_body(bone_name, Transform3D(Basis(x, direction, z), center), shape, mass_kg, swing, twist)

func add_body(bone_name: String, shape_rest: Transform3D, shape: Shape3D, mass_kg: float, swing: float, twist: float) -> void:
	if not allowed_bones.is_empty() and bone_name not in allowed_bones: return
	var body := PhysicalBone3D.new()
	body.name = "Physical_" + bone_name
	body.set("bone_name", bone_name)
	body.body_offset = rest(bone_name).affine_inverse() * shape_rest
	body.mass = mass_kg
	body.friction = 0.8
	body.bounce = 0.0
	body.linear_damp = 0.15
	body.angular_damp = 2.4 if bone_name.begins_with("foot") or bone_name.begins_with("forearm") else 1.2
	body.collision_layer = BODY_LAYER
	body.collision_mask = 1 | BODY_LAYER
	shape.margin = 0.005
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	simulator.add_child(body)
	PhysicsServer3D.body_set_enable_continuous_collision_detection(body.get_rid(), true)
	preload("res://player/ragdoll_mass_properties.gd").configure(body, shape)
	bodies[bone_name] = body
	# Joint limits on PhysicalBone3D are DEGREES, unlike Joint3D properties.
	if bone_name != "pelvis":
		var joint_basis: Basis
		if bone_name.begins_with("forearm") or bone_name.begins_with("shin"):
			# Hinge local Z follows the anatomical flexion axis in rest space.
			# Godot's positive hinge angle is rotation about NEGATIVE joint Z.
			var axis := rest(bone_name).basis.x.normalized()
			if bone_name.begins_with("shin"):
				axis = -axis
			var x := Vector3.UP.slide(axis).normalized()
			joint_basis = Basis(x, axis.cross(x), axis)
			body.joint_rotation = (shape_rest.basis.inverse() * joint_basis).get_euler()
			body.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			body.set("joint_constraints/angular_limit_enabled", true)
			body.set("joint_constraints/angular_limit_lower", -3.0)
			body.set("joint_constraints/angular_limit_upper", 125.0 if bone_name.begins_with("shin") else 135.0)
		else:
			# Cone twist local X is the twist axis, aligned with the bone.
			var axis := rest(bone_name).basis.y.normalized()
			var z := axis.cross(Vector3.RIGHT).normalized()
			joint_basis = Basis(axis, z.cross(axis).normalized(), z)
			body.joint_rotation = (shape_rest.basis.inverse() * joint_basis).get_euler()
			body.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			body.set("joint_constraints/swing_span", swing)
			body.set("joint_constraints/twist_span", twist)

