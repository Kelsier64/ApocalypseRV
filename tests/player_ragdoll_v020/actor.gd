extends CharacterBody3D
## Independent acceptance actor. No production Player or imported resource is edited.
const MODEL = preload("res://assets/models/player_test_v020/player_export_test_v020.glb")
const CLIP := &"TEST_v020_POSE_SAMPLES"
const BODY_LAYER := 128
var model: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var simulator: PhysicalBoneSimulator3D
var bodies: Dictionary = {}
var links: Array[Dictionary] = []
var controller_shape: CollisionShape3D
var ragdoll := false
var animation_time := 0.0
var animate := false
var move_request := Vector3.ZERO
var debug_shapes := false
var modified_poses: Array[Transform3D] = []

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	controller_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.60
	controller_shape.shape = capsule
	controller_shape.position.y = 0.80
	add_child(controller_shape)
	model = MODEL.instantiate()
	add_child(model)
	skeleton = model.get_node("PLAYER_Rig/Skeleton3D")
	# Physics owns the pose after animation, at the same fixed timestep.
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	animation = model.get_node("AnimationPlayer")
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play(CLIP)
	set_test_pose(0.0)
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "TEST_PhysicalBoneSimulator"
	skeleton.add_child(simulator)
	build_bodies()
	simulator.modification_processed.connect(_record_modified_pose)

func _physics_process(delta: float) -> void:
	if ragdoll:
		return
	if animate:
		animation_time = fmod(animation_time + delta, 8.0)
		animation.seek(animation_time, true)
	velocity.x = move_request.x * 1.5
	velocity.z = move_request.z * 1.5
	velocity.y -= 9.8 * delta
	move_and_slide()

func set_test_pose(time: float) -> void:
	animation_time = time
	animation.seek(time, true)
	skeleton.force_update_all_bone_transforms()

func build_bodies() -> void:
	add_box("pelvis", Vector3(0, 0.875, -0.035), Vector3(0.27, 0.18, 0.20), 12.0)
	add_box("spine_01", Vector3(0, 1.055, -0.045), Vector3(0.25, 0.14, 0.18), 8.0, 20.0, 15.0)
	add_box("spine_02", Vector3(0, 1.235, -0.040), Vector3(0.33, 0.20, 0.20), 14.0, 25.0, 20.0)
	add_capsule("head", Vector3(0, 1.475, -0.042), Vector3.UP, 0.105, 0.25, 4.5, 35.0, 45.0)
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
		add_box(foot, Vector3(x, 0.074, 0.035), Vector3(0.13, 0.135, 0.29), 1.25, 40.0, 20.0)
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
		bodies[pair[0]].add_collision_exception_with(bodies[pair[1]])
		bodies[pair[1]].add_collision_exception_with(bodies[pair[0]])
	# Isolated control capsule never participates in ragdoll collisions.
	simulator.physical_bones_add_collision_exception(get_rid())

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
	var body := PhysicalBone3D.new()
	body.name = "TEST_Physical_" + bone_name
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
	var debug_mesh := MeshInstance3D.new()
	debug_mesh.name = "TEST_CollisionPreview"
	if shape is BoxShape3D:
		var box := BoxMesh.new()
		box.size = shape.size
		debug_mesh.mesh = box
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = shape.radius
		capsule.height = shape.height
		debug_mesh.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.85, 1.0, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_mesh.material_override = material
	debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	debug_mesh.visible = debug_shapes
	body.add_child(debug_mesh)

func start_ragdoll(impulse := Vector3.ZERO) -> void:
	if ragdoll:
		return
	ragdoll = true
	animate = false
	move_request = Vector3.ZERO
	controller_shape.disabled = true
	# Preserve the current TEST pose, then relinquish animation ownership.
	animation.pause()
	simulator.physical_bones_start_simulation()
	for body: PhysicalBone3D in bodies.values():
		body.linear_velocity = velocity
		body.angular_velocity = Vector3.ZERO
	bodies["spine_02"].apply_central_impulse(impulse)

func recover_at(feet: Vector3) -> void:
	# Deliberate no-get-up-animation reset in this fixture; caller provides
	# a ground-tested, unobstructed standing position before enabling control.
	simulator.physical_bones_stop_simulation()
	ragdoll = false
	for body: PhysicalBone3D in bodies.values():
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis.IDENTITY, feet)
	velocity = Vector3.ZERO
	move_request = Vector3.ZERO
	animate = false
	animation.play(CLIP)
	set_test_pose(0.0)
	controller_shape.disabled = false

func set_debug(enabled: bool) -> void:
	debug_shapes = enabled
	for body: PhysicalBone3D in bodies.values():
		body.get_node("TEST_CollisionPreview").visible = enabled

func _record_modified_pose() -> void:
	modified_poses.clear()
	for i in skeleton.get_bone_count():
		modified_poses.append(skeleton.get_bone_global_pose(i))

func configuration() -> Array:
	var result: Array = []
	for bone_name: String in bodies:
		var body: PhysicalBone3D = bodies[bone_name]
		var shape: Shape3D = body.get_child(0).shape
		var limits: Dictionary = {}
		for prop in body.get_property_list():
			if String(prop.name).begins_with("joint_constraints/"):
				limits[prop.name] = body.get(prop.name)
		result.append({"bone": bone_name, "mass_kg": body.mass, "inertia_kg_m2": str(PhysicsServer3D.body_get_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_INERTIA)), "angular_damp": body.angular_damp, "linear_damp": body.linear_damp, "shape": shape.get_class(), "size": str(shape.size) if shape is BoxShape3D else [shape.radius, shape.height], "joint_type": body.joint_type, "joint_rotation_rad": str(body.joint_rotation), "limits_degrees": limits, "excluded": body.get_collision_exceptions().map(func(b): return b.name)})
	return result
