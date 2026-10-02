extends Node
## Raker owns health/loot. This owns only the transient physical pose and recovery.
const BODY_LAYER := 128
const RECOVERY_DELAY := 2.5
const RECOVERY_BLEND := 0.8
var actor: Raker
var visual: Node3D
var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var recovery_pose: SkeletonModifier3D
var bodies: Dictionary = {}
var links: Array[Dictionary] = []
var active := false
var pending := false
var elapsed := 0.0
var settled := 0.0
var recovering := 0.0
var launch_velocity := Vector3.ZERO
var impact_direction := Vector3.ZERO
var impact_point := Vector3.ZERO
var impact_speed := 0.0
var visual_rest := Transform3D.IDENTITY
var saved_layer := 1
var saved_mask := 1
var model_scale := 1.0
var restored_state: Dictionary = {}

func _ready() -> void:
	actor = get_parent()
	visual = actor.get_node("BodyMesh")
	skeleton = visual.skeleton
	visual_rest = visual.transform
	saved_layer = actor.collision_layer
	saved_mask = actor.collision_mask

func is_busy() -> bool:
	return pending or active or recovering > 0.0

func capture_snapshot() -> Dictionary:
	if not active: return {}
	var world_poses := _world_poses()
	var poses: Array[Transform3D] = []
	for bone in world_poses.size():
		var parent := skeleton.get_bone_parent(bone)
		poses.append(world_poses[parent].affine_inverse() * world_poses[bone] if parent >= 0 else skeleton.global_transform.affine_inverse() * world_poses[bone])
	return {"visual_transform": visual.global_transform, "poses": poses, "linear": bodies["pelvis"].linear_velocity}

func restore_snapshot(state: Dictionary) -> void:
	restored_state = state
	request(state.linear)

func _world_poses() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		var bone_name := String(skeleton.get_bone_name(bone))
		var parent := skeleton.get_bone_parent(bone)
		if bodies.has(bone_name):
			var body: PhysicalBone3D = bodies[bone_name]
			result.append(body.global_transform * body.body_offset.affine_inverse())
		elif parent >= 0: result.append(result[parent] * skeleton.get_bone_pose(bone))
		else: result.append(skeleton.global_transform * skeleton.get_bone_pose(bone))
	return result

func request(inherited: Vector3, direction := Vector3.ZERO, point := Vector3.ZERO, speed := 0.0) -> void:
	if active: return # A lethal follow-up keeps the existing physical momentum.
	launch_velocity = inherited.limit_length(28.0)
	impact_direction = direction
	impact_point = point
	impact_speed = speed
	if pending: return
	pending = true
	actor.grab.cancel("vehicle_impact" if speed > 0.0 else "death")
	actor.strike_elapsed = -1.0
	actor.strike_target = {}
	actor.vehicle_sprint_speed = 0.0
	actor.impact_stagger_remaining = 0.0
	visual.animation_player.pause()
	if recovering > 0.0:
		# A killing hit halfway through getting up must fall from the blended
		# visible pose, not the idle pose underneath the recovery modifier.
		for bone in recovery_pose.poses.size():
			skeleton.set_bone_pose(bone, skeleton.get_bone_pose(bone).interpolate_with(recovery_pose.poses[bone], recovery_pose.weight))
	# Contacts may arrive while Jolt is flushing queries. No collision mutation
	# or new physical bodies until the end of that flush.
	_start.call_deferred()

func _start() -> void:
	if not pending or not is_inside_tree() or actor.is_queued_for_deletion(): return
	# Disabled actors (including staged/retiring worlds) have no Jolt space.
	# Keep the request until processing resumes instead of applying an impulse
	# to removed bodies or letting a deferred call bypass scene suspension.
	if not actor.can_process(): return
	if simulator == null: _build()
	pending = false
	active = true
	elapsed = 0.0
	settled = 0.0
	recovering = 0.0
	recovery_pose.weight = 0.0
	visual.pose_modifier.active = false
	visual.pose_modifier.world_positions.clear()
	var placement := visual.global_transform
	visual.top_level = true
	visual.global_transform = placement
	if not restored_state.is_empty():
		visual.global_transform = restored_state.visual_transform
		for bone in skeleton.get_bone_count(): skeleton.set_bone_pose(bone, restored_state.poses[bone])
	actor.rv_support.clear()
	actor.boarding.release("impact", actor)
	actor.released_carrier_velocity = Vector3.ZERO
	actor.climb_carrier_velocity = Vector3.ZERO
	actor.post_climb_transfer_time_remaining = 0.0
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.body_collision_shape.disabled = true
	actor.get_node("HitBox").monitoring = false
	skeleton.force_update_all_bone_transforms()
	for body: PhysicalBone3D in bodies.values():
		body.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(body.get_bone_id()) * body.body_offset
		body.collision_layer = BODY_LAYER
		body.collision_mask = 1
	if impact_speed > 0.0 and restored_state.is_empty():
		# Hands/feet can extend beyond the walking capsule into the bumper at
		# contact. Separate the whole pose along that real contact plane before
		# enabling joints, instead of letting deep penetration fold it into RV.
		var clearance := 0.0
		for body: PhysicalBone3D in bodies.values():
			var shape: Shape3D = body.get_child(0).shape
			var normal := body.global_basis.inverse() * impact_direction
			var extent: float
			if shape is BoxShape3D: extent = normal.abs().dot(shape.size * .5)
			else: extent = shape.radius + absf(normal.y) * (shape.height*.5-shape.radius)
			clearance = maxf(clearance, extent + .04 - (body.global_position-impact_point).dot(impact_direction))
		var separation := impact_direction * minf(clearance, 1.2)
		visual.global_position += separation
		for body: PhysicalBone3D in bodies.values():
			body.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(body.get_bone_id()) * body.body_offset
	simulator.active = true
	simulator.physical_bones_start_simulation()
	var spin := Vector3.UP.cross(impact_direction).normalized() * minf(impact_speed * 0.12, 2.4)
	for body: PhysicalBone3D in bodies.values():
		body.linear_velocity = launch_velocity
		body.angular_velocity = spin
	# Contact height/side produces a local twist in addition to shared launch.
	var chest: PhysicalBone3D = bodies["spine_03"]
	var kick := impact_direction * minf(impact_speed, 14.0) * 0.7
	if kick.is_zero_approx(): kick = -actor.global_basis.z * 4.0
	var lever := (impact_point - chest.global_position).limit_length(0.45) if impact_speed > 0.0 else Vector3.ZERO
	if restored_state.is_empty(): chest.apply_impulse(kick, lever)
	restored_state = {}

func tick(delta: float) -> void:
	if pending:
		_start.call_deferred()
		return
	if recovering > 0.0:
		recovering = maxf(0.0, recovering - delta)
		recovery_pose.weight = smoothstep(0.0, RECOVERY_BLEND, recovering)
		actor.velocity.y -= actor.gravity * delta
		actor.move_and_slide()
		if recovering <= 0.0:
			visual.pose_modifier.active = true
			actor.reaction_remaining = 0.0
		return
	if not active: return
	elapsed += delta
	var pelvis: PhysicalBone3D = bodies["pelvis"]
	# Root follows the physical body for distance culling; detached visuals keep
	# their world frame, so this cannot apply the displacement twice.
	actor.global_position = pelvis.global_position - Vector3.UP * 1.3
	actor.velocity = pelvis.linear_velocity
	if actor.is_dead: return
	var speed := 0.0
	for body: PhysicalBone3D in bodies.values(): speed = maxf(speed, body.linear_velocity.length())
	settled = settled + delta if speed < 1.0 else 0.0
	if elapsed >= RECOVERY_DELAY and settled >= 0.35:
		settled = 0.0
		var stand := recovery_position()
		if stand.is_finite(): _recover.call_deferred(stand)

func recovery_position() -> Vector3:
	var center: Vector3 = bodies["pelvis"].global_position
	var space := actor.get_world_3d().direct_space_state
	var excluded: Array[RID] = [actor.get_rid()]
	for body: PhysicalBone3D in bodies.values(): excluded.append(body.get_rid())
	# Only nearby floor below the body. Never teleport to a ceiling or through
	# the RV to get up; an obstructed survivor remains down and retries.
	for offset in [Vector3.ZERO, Vector3(0.45,0,0), Vector3(-0.45,0,0), Vector3(0,0,0.45), Vector3(0,0,-0.45)]:
		var candidate: Vector3 = center + offset
		var ray := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 0.15, candidate - Vector3.UP * 2.0, saved_mask, excluded)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.7: continue
		if hit.collider is RigidBody3D and ClimbMath.point_velocity(hit.collider, hit.position).length() > 1.0: continue
		var stand: Vector3 = hit.position + Vector3.UP * (0.03 - actor.FOOT_OFFSET)
		var shape := CapsuleShape3D.new()
		shape.radius = actor.body_collision_shape.shape.radius
		shape.height = actor.STANDING_HEIGHT
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(actor.global_basis, stand + Vector3.UP * (actor.FOOT_OFFSET + shape.height * 0.5))
		query.collision_mask = saved_mask
		query.exclude = excluded
		if space.intersect_shape(query, 1).is_empty(): return stand
	return Vector3.INF

func _recover(stand: Vector3) -> void:
	if not active or actor.is_dead or actor.is_queued_for_deletion(): return
	# Recheck clearance after the deferred boundary (the vehicle can move).
	stand = recovery_position()
	if not stand.is_finite(): return
	var world_poses := _world_poses()
	simulator.physical_bones_stop_simulation()
	simulator.active = false
	for body: PhysicalBone3D in bodies.values():
		body.collision_layer = 0
		body.collision_mask = 0
	actor.global_position = stand
	visual.top_level = false
	visual.transform = visual_rest
	# Root is fixed by authored clips. Transfer its old world offset into pelvis
	# so the blend rises from the floor without stretching any limb segments.
	recovery_pose.poses.clear()
	var inv := skeleton.global_transform.affine_inverse()
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		var pose := skeleton.get_bone_rest(bone)
		if parent >= 0:
			pose = world_poses[parent].affine_inverse() * world_poses[bone]
			if String(skeleton.get_bone_name(parent)) == "root": pose = inv * world_poses[bone]
		recovery_pose.poses.append(pose)
	skeleton.reset_bone_poses()
	actor.set_crouched(false)
	actor.collision_layer = saved_layer
	actor.collision_mask = saved_mask
	actor.body_collision_shape.disabled = false
	actor.get_node("HitBox").monitoring = true
	actor.velocity = Vector3.ZERO
	actor.nav_has_target = false
	actor.has_last_flat_position = false
	actor.vehicle_impact_cooldown = RECOVERY_BLEND
	actor.boarding.recovery = RECOVERY_BLEND
	actor.climb_reenter_cooldown_remaining = RECOVERY_BLEND
	visual.locked = 0.0
	visual.play("idle", 1.0, true, 0.0)
	active = false
	recovering = RECOVERY_BLEND
	recovery_pose.weight = 1.0

func _build() -> void:
	var poses: Array[Transform3D] = []
	for bone in skeleton.get_bone_count(): poses.append(skeleton.get_bone_pose(bone))
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	model_scale = skeleton.global_basis.get_scale().x
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	recovery_pose = preload("res://enemies/raker_recovery_pose.gd").new()
	skeleton.add_child(recovery_pose)
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "RakerPhysicalBones"
	simulator.active = false
	skeleton.add_child(simulator)
	_box("pelvis", Vector3(0,1.10,-.09), Vector3(.31,.22,.23), 15.0)
	_segment("spine_01", "spine_02", .135, 9.0, 18.0, 12.0)
	_segment("spine_02", "spine_03", .16, 12.0, 20.0, 15.0)
	_box("spine_03", Vector3(0,1.71,-.05), Vector3(.40,.24,.25), 15.0, 22.0, 18.0)
	_capsule("head", Vector3(0,2.07,.025), Vector3.UP, .12, .27, 5.0, 35.0, 40.0)
	for side in ["L", "R"]:
		_segment("upper_arm_"+side, "forearm_"+side, .064, 3.0, 70.0, 45.0)
		_segment("forearm_"+side, "hand_"+side, .058, 3.0, 0.0, 0.0, .16)
		_segment("thigh_"+side, "shin_"+side, .088, 8.0, 65.0, 25.0)
		_segment("shin_"+side, "foot_"+side, .066, 5.0, 0.0, 0.0)
		_box("foot_"+side, Vector3(_rest("foot_"+side).origin.x,.085,.07), Vector3(.17,.15,.37), 2.5, 35.0, 20.0)
	for body: PhysicalBone3D in bodies.values():
		var parent := skeleton.get_bone_parent(body.get_bone_id())
		while parent >= 0 and not bodies.has(String(skeleton.get_bone_name(parent))): parent = skeleton.get_bone_parent(parent)
		if parent < 0: continue
		var other: PhysicalBone3D = bodies[String(skeleton.get_bone_name(parent))]
		links.append({"child": body, "parent": other, "parent_frame": other.global_transform.affine_inverse() * body.global_transform * body.joint_offset})
	simulator.physical_bones_add_collision_exception(actor.get_rid())
	for bone in poses.size(): skeleton.set_bone_pose(bone, poses[bone])
	skeleton.force_update_all_bone_transforms()

func _rest(bone: String) -> Transform3D:
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone))

func _segment(bone: String, end_bone: String, radius: float, mass_kg: float, swing: float, twist: float, extension := 0.0) -> void:
	var start := _rest(bone).origin
	var end := _rest(end_bone).origin
	var direction := (end-start).normalized()
	end += direction * extension
	_capsule(bone, (start+end)*0.5, direction, radius, start.distance_to(end), mass_kg, swing, twist)

func _box(bone: String, center: Vector3, size: Vector3, mass_kg: float, swing := 0.0, twist := 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size * model_scale
	_body(bone, Transform3D(Basis.IDENTITY, center), shape, mass_kg, swing, twist)

func _capsule(bone: String, center: Vector3, direction: Vector3, radius: float, height: float, mass_kg: float, swing: float, twist: float) -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = radius * model_scale
	shape.height = maxf(height, radius*2.0) * model_scale
	var z := Vector3.RIGHT.cross(direction).normalized()
	_body(bone, Transform3D(Basis(direction.cross(z), direction, z), center), shape, mass_kg, swing, twist)

func _body(bone: String, shape_rest: Transform3D, shape: Shape3D, mass_kg: float, swing: float, twist: float) -> void:
	var body := PhysicalBone3D.new()
	body.name = "Physical_" + bone
	body.set("bone_name", bone)
	# Imported visuals are 1.2x. Bake scale into primitives and cancel it in
	# the body's basis so Jolt always receives scale-one physical transforms.
	var offset := _rest(bone).affine_inverse() * shape_rest
	offset.basis = offset.basis.scaled(Vector3.ONE / model_scale)
	body.body_offset = offset
	body.mass = mass_kg
	body.friction = .8
	body.linear_damp = .18
	body.angular_damp = 2.4 if bone.begins_with("foot") or bone.begins_with("forearm") else 1.2
	body.collision_layer = 0
	body.collision_mask = 0
	shape.margin = .005
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	simulator.add_child(body)
	PhysicsServer3D.body_set_enable_continuous_collision_detection(body.get_rid(), true)
	preload("res://player/ragdoll_mass_properties.gd").configure(body, shape)
	bodies[bone] = body
	if bone == "pelvis": return
	var joint_basis: Basis
	if bone.begins_with("forearm") or bone.begins_with("shin"):
		var axis := _rest(bone).basis.x.normalized()
		if bone.begins_with("shin"): axis = -axis
		var x := Vector3.UP.slide(axis).normalized()
		joint_basis = Basis(x, axis.cross(x), axis)
		body.joint_rotation = (shape_rest.basis.inverse() * joint_basis).get_euler()
		body.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
		body.set("joint_constraints/angular_limit_enabled", true)
		body.set("joint_constraints/angular_limit_lower", -3.0)
		body.set("joint_constraints/angular_limit_upper", 125.0)
	else:
		var axis := _rest(bone).basis.y.normalized()
		var z := axis.cross(Vector3.RIGHT).normalized()
		joint_basis = Basis(axis, z.cross(axis), z)
		body.joint_rotation = (shape_rest.basis.inverse() * joint_basis).get_euler()
		body.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		body.set("joint_constraints/swing_span", swing)
		body.set("joint_constraints/twist_span", twist)
