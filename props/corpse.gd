class_name CorpseProp
extends Item
## Frozen interaction proxy; the existing anatomical bones own loose/held physics.
const PLAYER_MODEL = preload("res://assets/models/player_test_v020/player_export_test_v020.glb")
const RAKER_MODEL = preload("res://assets/models/raker/raker.glb")
const DISMEMBERMENT = preload("res://player/player_dismemberment_visual.gd")
var kind := "raker"
var body_state := PlayerBodyState.new()
var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var bodies: Dictionary = {}
var visual: Node3D
var builder: Node
var source_actor: WeakRef
var saved_pose: Dictionary = {}
var held := false
var processing := false
var physical_feed := false
var fed_bones: Dictionary = {}
var initialized := false
const HOLD_FREQUENCY := 36.0
var held_pelvis_rest := Transform3D.IDENTITY
var previous_hold_target := Transform3D.IDENTITY
var held_chest_rest := Transform3D.IDENTITY
var previous_chest_target := Transform3D.IDENTITY

func _ready() -> void:
	super._ready()
	process_physics_priority = 4
	_initialize.call_deferred()

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary or not data.get("version") is int or data.version != 1: return false
	if data.get("kind") not in ["player", "raker"]: return false
	if not PlayerBodyState.valid_state(data.get("body")): return false
	if not CheckpointSchema.valid_transform(data.get("visual_transform")): return false
	if not data.get("poses") is Array or data.poses.size() != (41 if data.kind == "player" else 54): return false
	for pose in data.poses:
		if not CheckpointSchema.valid_transform(pose): return false
	return true

func capture_item_state() -> Dictionary:
	var state := super.capture_item_state()
	state["corpse"] = _capture_pose() if initialized else saved_pose.duplicate(true)
	return state

func restore_item_state(state: Dictionary) -> void:
	super.restore_item_state(state)
	is_large = true
	var data: Dictionary = state.get("corpse", {})
	if not valid_state(data): return
	saved_pose = data.duplicate(true)
	kind = data.kind
	body_state.restore(data.body)
	item_name = "玩家屍體" if kind == "player" else "裂爪屍體"
	if initialized:
		_rebuild.call_deferred()

func set_held(value: bool) -> void:
	held = value

func confirm_placement(pose: Transform3D, parent: Node3D, support: Node3D = null) -> void:
	super.confirm_placement(pose, parent, support)
	if is_fixed: set_processing(true)

func detach_from_support() -> void:
	super.detach_from_support()
	if initialized and processing and not is_instance_valid(processing_owner): set_processing(false)

func _capture_pose() -> Dictionary:
	var world_poses: Array[Transform3D] = []
	var poses: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		var key := String(skeleton.get_bone_name(bone))
		var pose: Transform3D
		if physical_feed and fed_bones.has(key):
			pose = fed_bones[key]
		elif bodies.has(key) and (not processing or physical_feed):
			pose = bodies[key].global_transform * bodies[key].body_offset.affine_inverse()
		else:
			pose = (world_poses[parent] if parent >= 0 else skeleton.global_transform) * skeleton.get_bone_pose(bone)
		world_poses.append(pose)
		poses.append((world_poses[parent] if parent >= 0 else skeleton.global_transform).affine_inverse() * pose)
	return {"version": 1, "kind": kind, "body": body_state.capture(),
		"visual_transform": global_transform.affine_inverse() * skeleton.global_transform, "poses": poses}

## Move the running monster rig without restarting joints or losing impact momentum.
func adopt_raker(actor: Raker) -> void:
	kind = "raker"
	item_name = "裂爪屍體"
	source_actor = weakref(actor)
	var control: Node = actor.ragdoll
	skeleton = control.skeleton
	simulator = control.simulator
	bodies = control.bodies.duplicate()
	visual = control.visual
	global_position = bodies["pelvis"].global_position
	visual.reparent(self, true)
	visual.set_process(false)
	visual.set_physics_process(false)
	initialized = true
	freeze = true
	collision_layer = 2
	collision_mask = 0

static func leave_player(actor: CharacterBody3D) -> CorpseProp:
	var control: Node = actor.ragdoll_control
	var corpse: CorpseProp = load("res://props/corpse.tscn").instantiate()
	corpse.kind = "player"
	corpse.item_name = "玩家屍體"
	corpse.body_state.restore(actor.body_state.capture())
	var parent := WorldEntities.get_container(actor)
	if not WorldEntities.same_world(actor, parent): parent = actor.get_parent()
	parent.add_child(corpse)
	corpse.global_position = control.bodies["pelvis"].global_position
	# Read the evaluated physical frames, not the reset animation pose.
	corpse.skeleton = control.skeleton
	corpse.bodies = control.bodies
	corpse.saved_pose = corpse._capture_pose()
	corpse.linear_velocity = control.bodies["pelvis"].linear_velocity
	corpse.skeleton = null
	corpse.bodies = {}
	return corpse

func _rebuild() -> void:
	if not is_inside_tree(): return
	_retire_source()
	if is_instance_valid(visual): visual.free()
	if is_instance_valid(builder): builder.free()
	builder = null
	bodies.clear()
	initialized = false
	processing = false
	physical_feed = false
	fed_bones.clear()
	_initialize()

func _initialize() -> void:
	if initialized or not is_inside_tree() or not can_process(): return
	freeze = true
	collision_layer = 0 if held or is_instance_valid(processing_owner) else 2
	collision_mask = 0
	visual = (PLAYER_MODEL if kind == "player" else RAKER_MODEL).instantiate()
	for animation: AnimationPlayer in visual.find_children("*", "AnimationPlayer", true, false):
		animation.active = false
	add_child(visual)
	skeleton = visual.find_child("Skeleton3D", true, false)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	if kind == "raker":
		visual.scale = Vector3.ONE * 1.2
		builder = preload("res://enemies/raker_ragdoll.gd").new()
		builder.model_scale = 1.2
	else:
		builder = preload("res://player/player_ragdoll.gd").new()
		builder.allowed_bones.assign(["pelvis", "spine_01", "spine_02"])
		if body_state.has_part(&"head"): builder.allowed_bones.append("head")
		for side in ["L", "R"]:
			var prefix := "left" if side == "L" else "right"
			if body_state.has_part(prefix + "_arm"): builder.allowed_bones.append_array(["upper_arm_" + side, "forearm_" + side])
			if body_state.has_part(prefix + "_leg"): builder.allowed_bones.append_array(["thigh_" + side, "shin_" + side, "foot_" + side])
		_apply_missing_parts()
	builder.skeleton = skeleton
	simulator = PhysicalBoneSimulator3D.new()
	simulator.active = false
	skeleton.add_child(simulator)
	builder.simulator = simulator
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	builder.build_bodies()
	bodies = builder.bodies
	# Skeleton's world frame stays fixed while the lightweight proxy follows pelvis.
	var frame := skeleton.global_transform
	skeleton.top_level = true
	skeleton.global_transform = frame
	if not saved_pose.is_empty() and not held:
		skeleton.global_transform = global_transform * saved_pose.visual_transform
		for bone in skeleton.get_bone_count(): skeleton.set_bone_pose(bone, saved_pose.poses[bone])
	else:
		var basis := global_basis * Basis(Vector3.FORWARD, PI * .5) if held else global_basis
		var scale_factor := 1.2 if kind == "raker" else 1.0
		basis = basis.scaled(Vector3.ONE * scale_factor)
		var center := skeleton.get_bone_global_rest(skeleton.find_bone("pelvis")).origin
		if held:
			var hip: Transform3D = skeleton.get_bone_global_rest(skeleton.find_bone("pelvis")) * bodies["pelvis"].body_offset
			var chest: PhysicalBone3D = bodies["spine_03" if kind == "raker" else "spine_02"]
			var upper: Transform3D = skeleton.get_bone_global_rest(chest.get_bone_id()) * chest.body_offset
			center = (hip.origin + upper.origin) * .5
		skeleton.global_transform = Transform3D(basis, global_position - basis * center)
	skeleton.force_update_all_bone_transforms()
	for body: PhysicalBone3D in bodies.values():
		body.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(body.get_bone_id()) * body.body_offset
		body.collision_layer = 0 if held else 128
		body.collision_mask = 0 if held else 1
	if held:
		held_pelvis_rest = global_transform.affine_inverse() * bodies["pelvis"].global_transform
		previous_hold_target = global_transform * held_pelvis_rest
		var chest: PhysicalBone3D = bodies["spine_03" if kind == "raker" else "spine_02"]
		held_chest_rest = global_transform.affine_inverse() * chest.global_transform
		previous_chest_target = global_transform * held_chest_rest
		chest.mass *= 6.0
		# Both supported ends resist the weight of the hanging limbs.
		bodies["pelvis"].mass *= 6.0
		for body: PhysicalBone3D in bodies.values():
			body.linear_damp = .6
			body.angular_damp = maxf(body.angular_damp, 2.8)
	simulator.active = true
	simulator.physical_bones_start_simulation()
	for body: PhysicalBone3D in bodies.values(): body.linear_velocity = linear_velocity
	initialized = true
	if is_instance_valid(processing_owner) or is_fixed or (presentation_only and not held): set_processing(true)
	if presentation_only and is_being_placed: _apply_ghost_material(visual)

func held_support_center() -> Vector3:
	return Vector3(0, 1.52, -.37)

func update_held_grips() -> void:
	if not initialized or not held: return
	# Support the actual hip and chest from below, on either side of the torso
	# midpoint. Both palms follow the live ragdoll instead of an empty proxy.
	# Seat the body 5 cm deeper into the palms while retaining the hand reach.
	var chest: PhysicalBone3D = bodies["spine_03" if kind == "raker" else "spine_02"]
	$GripLeft.global_position = bodies["pelvis"].global_position + global_basis * Vector3(0, -.14, .04)
	$GripRight.global_position = chest.global_position + global_basis * Vector3(0, -.16, .05)

func _follow_hand(delta: float) -> void:
	previous_hold_target = _follow_support(bodies["pelvis"], held_pelvis_rest, previous_hold_target, delta)
	previous_chest_target = _follow_support(bodies["spine_03" if kind == "raker" else "spine_02"], held_chest_rest, previous_chest_target, delta)

func _follow_support(support: PhysicalBone3D, rest: Transform3D, previous_target: Transform3D, delta: float) -> Transform3D:
	var target := global_transform * rest
	var target_velocity := ((target.origin - previous_target.origin) / maxf(delta, .001)).limit_length(14.0)
	var error := support.global_position - target.origin
	var relative_velocity := support.linear_velocity - target_velocity
	# Critically damped response replaces the original underdamped velocity chase.
	# Feed-forward follows a moving hand without building a large spring offset.
	var damping := exp(-HOLD_FREQUENCY * delta)
	var next_relative := (relative_velocity - HOLD_FREQUENCY * (relative_velocity + HOLD_FREQUENCY * error) * delta) * damping
	support.linear_velocity = (target_velocity + next_relative + Vector3.UP * 9.8 * delta).limit_length(18.0)
	var rotation_error := (target.basis * support.global_basis.inverse()).get_rotation_quaternion().normalized()
	if rotation_error.w < 0: rotation_error = -rotation_error
	var turn := (target.basis * previous_target.basis.inverse()).get_rotation_quaternion().normalized()
	if turn.w < 0: turn = -turn
	var angular_target := turn.get_axis() * minf(turn.get_angle() / maxf(delta, .001), 6.0)
	angular_target += rotation_error.get_axis() * minf(rotation_error.get_angle() * 8.0, 8.0)
	support.angular_velocity = support.angular_velocity.lerp(angular_target, 1.0 - exp(-30.0 * delta))
	return target

func _apply_missing_parts() -> void:
	var injured := false
	for part in PlayerBodyState.PARTS: injured = injured or not body_state.has_part(part)
	if not injured: return
	var original: MeshInstance3D = skeleton.get_node("PLAYER_Mesh")
	var skin := original.skin
	var mesh_transform := original.transform
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false): mesh.hide()
	var donor := DISMEMBERMENT.DONOR.instantiate()
	for mesh: MeshInstance3D in donor.find_children("*", "MeshInstance3D", true, false):
		var label := String(mesh.name)
		var role := label.get_slice("_", 0)
		if role not in ["Part", "Wound"]: continue
		var part := "torso"
		for key in DISMEMBERMENT.ROOTS:
			if label.begins_with(role + "_" + key): part = key; break
		var present := part == "torso" or body_state.has_part(part)
		if (role == "Part" and not present) or (role == "Wound" and present): continue
		var data := {"mesh": DISMEMBERMENT._remap_mesh(mesh, skin), "skin": skin, "transform": mesh_transform}
		DISMEMBERMENT._instance(data, skeleton, label, 1)
	donor.free()

func begin_physical_feed() -> void:
	if not initialized or physical_feed: return
	# A service tick may precede the deferred queue-freeze callback.
	# Establish the waiting phase first so it cannot stop an active feed.
	if not processing: set_processing(true)
	physical_feed = true
	var frame := skeleton.global_transform
	skeleton.top_level = true
	skeleton.global_transform = frame
	skeleton.force_update_all_bone_transforms()
	for body: PhysicalBone3D in bodies.values():
		body.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(body.get_bone_id()) * body.body_offset
		body.collision_layer = 128
		body.collision_mask = 1
	simulator.active = true
	simulator.physical_bones_start_simulation()
	for body: PhysicalBone3D in bodies.values():
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

static func _clear_feed_joint(body: PhysicalBone3D) -> void:
	if body.joint_type == PhysicalBone3D.JOINT_TYPE_NONE: return
	var frame := body.global_transform
	var linear := body.linear_velocity
	var angular := body.angular_velocity
	var parent := body.get_parent()
	body.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	# NONE alone does not clear an existing server joint in Godot 4.7.2.
	# Leaving the tree clears it through the bone registration lifecycle.
	parent.remove_child(body)
	parent.add_child(body)
	body.global_transform = frame
	body.linear_velocity = linear
	body.angular_velocity = angular

func sever_feed_segment(key: String) -> void:
	if not physical_feed or not bodies.has(key): return
	var caught: PhysicalBone3D = bodies[key]
	_clear_feed_joint(caught)
	for body: PhysicalBone3D in bodies.values():
		var parent := skeleton.get_bone_parent(body.get_bone_id())
		while parent >= 0:
			var parent_key := String(skeleton.get_bone_name(parent))
			if bodies.has(parent_key):
				if parent_key == key: _clear_feed_joint(body)
				break
			parent = skeleton.get_bone_parent(parent)

func consume_feed_bones(keys: Array[String]) -> void:
	if not physical_feed or keys.is_empty(): return
	var data := _capture_pose()
	var frames: Dictionary = {}
	var motion: Dictionary = {}
	# Removing a simulated parent lets the engine reconnect its child to a
	# different ancestor. Stop the solver and detach those orphan joints first.
	for key: String in bodies:
		var body: PhysicalBone3D = bodies[key]
		frames[key] = body.global_transform
		motion[key] = [body.linear_velocity,body.angular_velocity,body.collision_layer,body.collision_mask]
		if key in keys: continue
		var parent := skeleton.get_bone_parent(body.get_bone_id())
		while parent >= 0:
			var parent_key := String(skeleton.get_bone_name(parent))
			if bodies.has(parent_key):
				if parent_key in keys: _clear_feed_joint(body)
				break
			parent = skeleton.get_bone_parent(parent)
	simulator.physical_bones_stop_simulation()
	for key in keys:
		if not bodies.has(key): continue
		var body: PhysicalBone3D = bodies[key]
		fed_bones[key] = frames[key]*body.body_offset.affine_inverse()
		# Retain the node until the whole rig is retired. Deleting a
		# parent PhysicalBone leaves cached parent pointers in surviving children.
		body.collision_layer = 0
		body.collision_mask = 0
		_clear_feed_joint(body)
		var retired: Node3D = visual.get_node_or_null("ConsumedBones")
		if retired == null:
			retired = Node3D.new()
			retired.name = "ConsumedBones"
			visual.add_child(retired)
		# Leave the simulator while the node is still alive so parent caches
		# update safely; retained nodes can never be restarted as descendants.
		body.reparent(retired,true)
		bodies.erase(key)
	# Preserve both the swallowed skin and every remaining solver frame.
	for i in skeleton.get_bone_count(): skeleton.set_bone_pose(i,data.poses[i])
	skeleton.force_update_all_bone_transforms()
	var remaining: Array[StringName] = []
	for key: String in bodies: remaining.append(StringName(key))
	if not remaining.is_empty(): simulator.physical_bones_start_simulation(remaining)
	for key: String in bodies:
		var body: PhysicalBone3D = bodies[key]
		body.global_transform = frames[key]
		body.linear_velocity = motion[key][0]
		body.angular_velocity = motion[key][1]
		body.collision_layer = motion[key][2]
		body.collision_mask = motion[key][3]

func set_processing(value: bool) -> void:
	if not initialized or value == processing: return
	if value:
		_retire_source()
		saved_pose = _capture_pose()
		simulator.physical_bones_stop_simulation()
		simulator.active = false
		for body: PhysicalBone3D in bodies.values(): body.collision_layer = 0; body.collision_mask = 0
		skeleton.top_level = false
		skeleton.global_transform = global_transform * saved_pose.visual_transform
		for bone in skeleton.get_bone_count(): skeleton.set_bone_pose(bone, saved_pose.poses[bone])
		processing = true
	else:
		saved_pose = _capture_pose()
		processing = false
		_rebuild()

func _physics_process(delta: float) -> void:
	if not initialized:
		_initialize.call_deferred()
		return
	if processing and not physical_feed: return
	if physical_feed and not fed_bones.is_empty():
		for key: String in fed_bones:
			skeleton.set_bone_global_pose(skeleton.find_bone(key),skeleton.global_transform.affine_inverse()*fed_bones[key])
		skeleton.force_update_all_bone_transforms()
	if held:
		_follow_hand(delta)
	else:
		if bodies.is_empty(): return
		var pelvis: PhysicalBone3D = bodies["pelvis"] if bodies.has("pelvis") else bodies.values()[0]
		global_position = pelvis.global_position
		linear_velocity = pelvis.linear_velocity
		angular_velocity = pelvis.angular_velocity

func _exit_tree() -> void:
	if _world_transfer: return
	super._exit_tree()
	if is_instance_valid(builder): builder.free()
	_retire_source()

func _retire_source() -> void:
	if source_actor != null:
		var actor: Node = source_actor.get_ref()
		if is_instance_valid(actor): actor.queue_free()
		source_actor = null
