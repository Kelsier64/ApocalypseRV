extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002
const CLIMB_WALL_MIN_DOT = 0.0
const CLIMB_WALL_MAX_DOT = 0.85
const CLIMB_MIN_HIT_Y = 0.1
const CLIMB_MAX_HIT_Y = 1.4
const CLIMB_EXIT_MAX_UP_VELOCITY = 0.1
const CLIMB_VERTICAL_SPEED = 2.6
const CLIMB_SIDE_SPEED = 1.2
const CLIMB_WALL_STICK_SPEED = 0.0
const CLIMB_CONTACT_GRACE_TIME = 0.6
const CLIMB_START_CEILING_CHECK_DISTANCE = 0.6
const CLIMB_MAX_RV_ANGULAR_SPEED = 2.4
const CLIMB_MAX_FRAME_DELTA = 1.5
const CLIMB_REENTER_COOLDOWN = 0.2
const CLIMB_WALL_ALIGN_OFFSET = 0.22
const CLIMB_WALL_MAX_OUTWARD_CORRECTION = 0.08
const CLIMB_DEBUG_LOG_ABORTS = false
const PropScript = preload("res://props/interactable_item.gd")

@onready var camera = $Camera3D

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

const MAX_SLOTS = PlayerInventory.MAX_SLOTS
var inventory := PlayerInventory.new()
var placement := EquipmentPlacement.new()
var held_item_node: Node3D = null

@export_group("Debug")
@export var debug_climb_messages: bool = false
@export var debug_climb_message_interval: float = 0.35

# UI State
var in_ui_mode: bool = false

# Top-level mode. The individual flags (in_ui_mode, placement state,
# seated_in, is_player_dead) remain the storage, but every transition must go
# through the enter_/exit_ helpers below so exclusivity is enforced in one
# place instead of ad-hoc at each call site.
enum PlayerMode { NORMAL, PLACING, UI, SEATED, DEAD }
var seated_in: Node3D = null

# Locomotion
enum LocomotionState { NORMAL, CLIMBING }
var locomotion_state: LocomotionState = LocomotionState.NORMAL
var active_climb_rv: Node3D = null
var previous_climb_rv_transform: Transform3D = Transform3D.IDENTITY
var active_wall_normal: Vector3 = Vector3.ZERO
var climb_carrier_velocity := Vector3.ZERO
var released_carrier_velocity := Vector3.ZERO
var rv_support := RVSupport.new()
var climb_contact_grace_remaining: float = 0.0
var climb_reenter_cooldown_remaining: float = 0.0
var debug_last_ceiling_hit_distance: float = INF
var debug_last_ceiling_hit_position: Vector3 = Vector3.ZERO
var debug_last_ceiling_hit_source: String = ""
var debug_last_ceiling_hit_node: String = ""
var debug_climb_last_log_time_by_tag: Dictionary = {}

# Health System
var max_player_health: float = 100.0
var current_player_health: float = 100.0
var damage_cooldown: float = 0.0
var is_player_dead: bool = false

@onready var inventory_ui = $InventoryUI
@onready var health_bar = $HealthBarUI
@onready var body_collision_shape = $CollisionShape3D
@onready var climb_wall_probe = $ClimbWallProbe
@onready var climb_upward_probe = $ClimbUpwardProbe

func add_prop_item(prop: Prop, path: String) -> bool:
	return add_item(prop.item_name, prop.is_large, path, prop.capture_item_state())

func add_item(item_name: String, is_large: bool, scene_path: String, state: Dictionary = {}) -> bool:
	if not inventory.add_item(item_name, is_large, scene_path, state):
		return false
	_update_inventory_display()
	if inventory.active_slot == inventory.items.size() - 1:
		_equip_active_slot()
	return true

func _update_inventory_display():
	if inventory_ui and inventory_ui.has_method("update_slots"):
		inventory_ui.update_slots(inventory.items, inventory.active_slot)

func _set_active_slot(index: int) -> void:
	if inventory.select_slot(index):
		_update_inventory_display()
		_equip_active_slot()

func _equip_active_slot():
	var hand_marker = camera.get_node_or_null("HandMarker")
	if not hand_marker:
		hand_marker = Marker3D.new()
		hand_marker.name = "HandMarker"
		# Position the hand lower right in front of the camera
		hand_marker.position = Vector3(0.5, -0.5, -0.8)
		camera.add_child(hand_marker)
		
	if is_instance_valid(held_item_node):
		held_item_node.queue_free()
		held_item_node = null
		
	if inventory.active_slot < inventory.items.size() and inventory.active_slot >= 0:
		var item_data = inventory.items[inventory.active_slot]
		var scene: PackedScene = load(item_data["scene_path"])
		if scene:
			held_item_node = scene.instantiate()
			_restore_prop_state(held_item_node, item_data)
			# Disable physics so it's just visual while held
			if held_item_node is RigidBody3D:
				held_item_node.freeze = true
				held_item_node.collision_layer = 0
				held_item_node.collision_mask = 0
				
			hand_marker.add_child(held_item_node)
			# World labels should not cover the interaction HUD in a held preview.
			for label in held_item_node.find_children("*", "Label3D", true, false):
				label.hide()
			
			# Apply visual holding offsets if it's our new Prop class
			if held_item_node is PropScript:
				held_item_node.position = held_item_node.hold_position
				held_item_node.rotation_degrees = held_item_node.hold_rotation
				held_item_node.scale = held_item_node.hold_scale
			else:
				held_item_node.transform = Transform3D.IDENTITY

func _ready():
	# Frozen RV panels need explicit support motion; avoid applying it twice.
	platform_floor_layers = 0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.current = true
	_update_inventory_display()
	_equip_active_slot()
	if climb_upward_probe:
		climb_upward_probe.enabled = true
		climb_upward_probe.collision_mask = 0xFFFFFFFF
		climb_upward_probe.collide_with_bodies = true
		climb_upward_probe.collide_with_areas = true
		climb_upward_probe.exclude_parent = true
	_sync_body_collision_to_locomotion()
	add_to_group(Groups.PLAYER)
	current_player_health = max_player_health
	_update_health_bar()

func is_placing_equipment() -> bool:
	return is_instance_valid(placement.placing_equipment)

func get_active_item_name() -> String:
	return inventory.active_item().get("name", "")

func consume_active_item() -> void:
	if inventory.consume_active():
		_update_inventory_display()
		_equip_active_slot()

func get_player_mode() -> PlayerMode:
	if is_player_dead:
		return PlayerMode.DEAD
	if seated_in != null:
		return PlayerMode.SEATED
	if in_ui_mode:
		return PlayerMode.UI
	if is_placing_equipment():
		return PlayerMode.PLACING
	return PlayerMode.NORMAL

## Modes are mutually exclusive: each enter_* helper only succeeds from NORMAL
## and returns whether the transition happened, so callers must not proceed
## with their side of the flow on a refusal.
func enter_equipment_placement(equip: Node3D) -> bool:
	if get_player_mode() != PlayerMode.NORMAL:
		return false
	placement.begin(equip)
	return true

func enter_ui_mode() -> bool:
	if get_player_mode() != PlayerMode.NORMAL:
		return false
	in_ui_mode = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	return true

func exit_ui_mode():
	in_ui_mode = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

## Seat flow: the player owns its own state mutation; the seat only decides
## where the player reappears and which camera takes over.
func enter_seat_mode(seat: Node3D) -> bool:
	if get_player_mode() != PlayerMode.NORMAL:
		return false
	_exit_climb_to_normal()
	rv_support.clear()
	velocity = Vector3.ZERO
	released_carrier_velocity = Vector3.ZERO
	seated_in = seat
	global_position = seat.global_position
	set_process_unhandled_input(false)
	body_collision_shape.disabled = true
	visible = false
	return true

func exit_seat_mode(exit_position: Vector3) -> void:
	if seated_in == null:
		return
	var rv := _find_rv_ancestor(seated_in)
	velocity = ClimbMath.point_velocity(rv, exit_position)
	released_carrier_velocity = velocity
	seated_in = null
	set_physics_process(true)
	set_process_unhandled_input(true)
	body_collision_shape.disabled = false
	visible = true
	global_position = exit_position
	camera.current = true

func drop_item():
	if inventory.active_slot >= 0 and inventory.active_slot < inventory.items.size():
		var item_data = inventory.items[inventory.active_slot]
		
		# Spawn it back into the world
		var scene: PackedScene = load(item_data["scene_path"])
		if scene:
			var dropped_item = scene.instantiate()
			_restore_prop_state(dropped_item, item_data)
			var entity_parent: Node = WorldEntities.get_container(self)
			if entity_parent == null:
				entity_parent = get_tree().current_scene
			entity_parent.add_child(dropped_item)
			
			# Position it in front of the player
			var drop_transform = global_transform
			# Move it forward by 1.5 meters
			drop_transform.origin -= transform.basis.z * 1.5
			# Move it up slightly so it doesn't clip into floor
			drop_transform.origin.y += 1.0
			dropped_item.global_transform = drop_transform
			
			# If it's a rigid body, give it a tiny toss forward
			if dropped_item is RigidBody3D:
				dropped_item.linear_velocity = -transform.basis.z * 3.0
			
		consume_active_item()

func _restore_prop_state(node: Node, data: Dictionary) -> void:
	if node is Prop:
		node.item_name = data["name"]
		node.is_large = data["is_large"]
		node.restore_item_state(data.get("state", {}))

func _unhandled_input(event):
	if in_ui_mode or is_player_dead: return
	
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate horizontal (body) normally
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		# Rotate vertical (camera)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		# Clamp vertical rotation to avoid flipping backward
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Mouse wheel to change slots
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_active_slot((inventory.active_slot - 1 + MAX_SLOTS) % MAX_SLOTS)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_active_slot((inventory.active_slot + 1) % MAX_SLOTS)
			
	# Number keys to change slots
	for slot in range(MAX_SLOTS):
		if event.is_action_pressed("hotbar_%d" % (slot + 1)):
			_set_active_slot(slot)
			break

	# Drop item
	if event.is_action_pressed("drop_item"):
		drop_item()

	placement.handle_input(self, event)

## Pure climb-start gate (test contract): W + RV hit + wall-like normal +
## valid hit height are all required; jump state must not matter.
func _can_begin_climb(_jump_pressed: bool, w_pressed: bool, is_rv_hit: bool, wall_normal_ok: bool, hit_height_ok: bool) -> bool:
	return w_pressed and is_rv_hit and wall_normal_ok and hit_height_ok

func _is_rv_wall_normal(hit_normal: Vector3, rv_up: Vector3 = Vector3.UP) -> bool:
	return ClimbMath.is_rv_wall_normal(hit_normal, rv_up, CLIMB_WALL_MIN_DOT, CLIMB_WALL_MAX_DOT)

func _is_valid_climb_hit_height(local_hit_y: float) -> bool:
	return ClimbMath.is_valid_hit_height(local_hit_y, CLIMB_MIN_HIT_Y, CLIMB_MAX_HIT_Y)

func _should_disable_body_collision_for_locomotion(_state: int) -> bool:
	return seated_in != null

func _sync_body_collision_to_locomotion() -> void:
	if body_collision_shape == null:
		return
	body_collision_shape.disabled = _should_disable_body_collision_for_locomotion(int(locomotion_state))

func _compute_rv_position_delta(prev_rv_transform: Transform3D, next_rv_transform: Transform3D) -> Vector3:
	return ClimbMath.rv_position_delta(prev_rv_transform, next_rv_transform)

func _sanitize_velocity_after_climb(v: Vector3) -> Vector3:
	return ClimbMath.sanitize_velocity_after_climb(v, CLIMB_EXIT_MAX_UP_VELOCITY)

func _debug_v3(v: Vector3) -> String:
	return ClimbMath.format_v3(v)

func _debug_node_name(node: Node) -> String:
	return ClimbMath.format_node_name(node)

func _debug_climb_side_label(rv: Node3D, wall_normal: Vector3) -> String:
	return ClimbMath.climb_side_label(rv, wall_normal)

func _debug_climb_log(tag: String, message: String, force: bool = false) -> void:
	if not debug_climb_messages:
		return
	var now: float = Time.get_ticks_msec() * 0.001
	if not force:
		var last: float = float(debug_climb_last_log_time_by_tag.get(tag, -INF))
		if now - last < maxf(0.01, debug_climb_message_interval):
			return
	debug_climb_last_log_time_by_tag[tag] = now
	print("[CLIMB_DEBUG][player][", tag, "] ", message)

func _build_climb_motion(rv_up: Vector3, wall_normal: Vector3, vertical_input: float, horizontal_input: float, delta: float) -> Vector3:
	return ClimbMath.build_climb_motion(rv_up, wall_normal, vertical_input, horizontal_input, delta,
		CLIMB_VERTICAL_SPEED, CLIMB_SIDE_SPEED, CLIMB_WALL_STICK_SPEED, CLIMB_MAX_FRAME_DELTA, transform.basis.x)

func _clamp_upward_climb_distance(rv_up: Vector3, desired_upward_distance: float) -> float:
	debug_last_ceiling_hit_distance = INF
	debug_last_ceiling_hit_position = Vector3.ZERO
	debug_last_ceiling_hit_source = ""
	debug_last_ceiling_hit_node = ""

	if desired_upward_distance <= 0.0:
		return 0.0

	var from := global_position + rv_up * 0.2
	var to := from + rv_up * (desired_upward_distance + 0.8)
	var hit := ClimbMath.nearest_ceiling_hit(climb_upward_probe, self, from, to)
	if hit.is_empty():
		return desired_upward_distance

	debug_last_ceiling_hit_distance = hit["distance"]
	debug_last_ceiling_hit_position = hit["position"]
	debug_last_ceiling_hit_source = hit["source"]
	debug_last_ceiling_hit_node = hit["node_label"]

	# Keep a small safety gap so we stop before interpenetrating the ceiling surface.
	var safe_distance: float = maxf(0.0, hit["distance"] - 0.05)
	return minf(desired_upward_distance, safe_distance)

func _move_with_climb_collision(step: Vector3) -> KinematicCollision3D:
	if step.length_squared() <= 0.0000001:
		return null
	return move_and_collide(step)

func _apply_wall_outward_alignment(rv_up: Vector3) -> void:
	if climb_wall_probe == null or not climb_wall_probe.is_colliding() or active_climb_rv == null:
		return

	var hit_node := climb_wall_probe.get_collider() as Node
	if _find_rv_ancestor(hit_node) != active_climb_rv:
		return

	var wall_normal: Vector3 = climb_wall_probe.get_collision_normal().normalized()
	if _is_rv_wall_normal(wall_normal, rv_up):
		active_wall_normal = wall_normal

	var desired_probe_position: Vector3 = climb_wall_probe.get_collision_point() + wall_normal * CLIMB_WALL_ALIGN_OFFSET
	var correction: Vector3 = desired_probe_position - climb_wall_probe.global_position
	var outward_mag: float = correction.dot(wall_normal)
	if outward_mag <= 0.0:
		return
	var outward_step: Vector3 = wall_normal * minf(outward_mag, CLIMB_WALL_MAX_OUTWARD_CORRECTION)
	_move_with_climb_collision(outward_step)

func _find_rv_ancestor(node: Node) -> Node3D:
	return ClimbMath.find_rv_ancestor(node)

func _process_normal_movement(delta: float) -> void:
	var had_support := is_instance_valid(rv_support.rv)
	var last_support_velocity := rv_support.carrier_velocity
	var was_supported := rv_support.follow(self, delta)
	var support_velocity := rv_support.carrier_velocity
	if had_support and not was_supported:
		released_carrier_velocity = last_support_velocity
		velocity.y += last_support_velocity.y
	if is_on_floor() and not (had_support and not was_supported):
		released_carrier_velocity = Vector3.ZERO
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	if Input.is_action_pressed("move_forward"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_back"):
		input_dir.y += 1

	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()

	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	velocity.x += released_carrier_velocity.x
	velocity.z += released_carrier_velocity.z
	move_and_slide()
	velocity.x -= released_carrier_velocity.x
	velocity.z -= released_carrier_velocity.z
	if not rv_support.capture(self) and was_supported:
		released_carrier_velocity = support_velocity
		velocity.y += support_velocity.y

func _try_start_climb() -> void:
	if locomotion_state != LocomotionState.NORMAL:
		return
	if climb_reenter_cooldown_remaining > 0.0:
		_debug_climb_log("start_cooldown", "blocked by reenter cooldown: %.2f" % climb_reenter_cooldown_remaining)
		return
	if not Input.is_action_pressed("move_forward"):
		return
	if climb_wall_probe == null or not climb_wall_probe.is_colliding():
		_debug_climb_log("start_probe_miss", "wall probe has no hit")
		return

	var hit_node := climb_wall_probe.get_collider() as Node
	var rv := _find_rv_ancestor(hit_node)
	if rv == null:
		return

	var hit_normal: Vector3 = climb_wall_probe.get_collision_normal()
	var hit_point: Vector3 = climb_wall_probe.get_collision_point()
	var local_hit_y: float = to_local(hit_point).y
	var rv_up: Vector3 = rv.global_transform.basis.y.normalized()
	var start_allowed_upward := _clamp_upward_climb_distance(rv_up, CLIMB_START_CEILING_CHECK_DISTANCE)
	if start_allowed_upward < CLIMB_START_CEILING_CHECK_DISTANCE:
		# Ceiling detected overhead: block entering climb state.
		_debug_climb_log(
			"start_ceiling_block",
			"side=%s allowed=%.2f wanted=%.2f hit_dist=%.2f src=%s hit_node=%s hit_pos=%s wall_n=%s" % [
				_debug_climb_side_label(rv, hit_normal),
				start_allowed_upward,
				CLIMB_START_CEILING_CHECK_DISTANCE,
				debug_last_ceiling_hit_distance,
				debug_last_ceiling_hit_source,
				debug_last_ceiling_hit_node,
				_debug_v3(debug_last_ceiling_hit_position),
				_debug_v3(hit_normal.normalized())
			]
		)
		return
	var wall_normal_ok := _is_rv_wall_normal(hit_normal, rv_up)
	var hit_height_ok := _is_valid_climb_hit_height(local_hit_y)
	# W-pressed and RV-hit are already guaranteed by the early returns above.
	if not _can_begin_climb(false, true, true, wall_normal_ok, hit_height_ok):
		_debug_climb_log(
			"start_gate_reject",
			"side=%s wall_ok=%s hit_y=%.2f range=[%.2f, %.2f] wall_dot_up=%.2f" % [
				_debug_climb_side_label(rv, hit_normal),
				str(wall_normal_ok),
				local_hit_y,
				CLIMB_MIN_HIT_Y,
				CLIMB_MAX_HIT_Y,
				absf(hit_normal.normalized().dot(rv_up))
			]
		)
		return

	locomotion_state = LocomotionState.CLIMBING
	rv_support.clear()
	active_climb_rv = rv
	previous_climb_rv_transform = rv.global_transform
	active_wall_normal = hit_normal.normalized()
	climb_contact_grace_remaining = CLIMB_CONTACT_GRACE_TIME
	climb_carrier_velocity = ClimbMath.point_velocity(rv, global_position)
	released_carrier_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	_debug_climb_log(
		"start_ok",
		"entered climbing side=%s wall_n=%s hit_y=%.2f" % [
			_debug_climb_side_label(rv, hit_normal),
			_debug_v3(active_wall_normal),
			local_hit_y
		],
		true
	)

func _apply_rv_delta_compensation() -> void:
	if active_climb_rv == null or not is_instance_valid(active_climb_rv):
		return
	var next_transform := active_climb_rv.global_transform
	var delta_pos := ClimbMath.attachment_delta(previous_climb_rv_transform, next_transform, global_position)
	if delta_pos.length() > CLIMB_MAX_FRAME_DELTA:
		climb_carrier_velocity = Vector3.ZERO
		_abort_climb("rv teleported")
		return
	var rotation_delta := next_transform.basis * previous_climb_rv_transform.basis.inverse()
	active_wall_normal = (rotation_delta * active_wall_normal).normalized()
	rotate_y(rotation_delta.get_euler().y)
	climb_carrier_velocity = delta_pos / get_physics_process_delta_time()
	var collision := _move_with_climb_collision(delta_pos)
	if collision and _find_rv_ancestor(collision.get_collider()) == active_climb_rv:
		active_wall_normal = collision.get_normal().normalized()
	previous_climb_rv_transform = next_transform
	climb_wall_probe.force_raycast_update()

func _process_climbing(delta: float) -> void:
	if active_climb_rv == null or not is_instance_valid(active_climb_rv):
		_abort_climb("rv invalid")
		return

	# Manual detach: pressing back or jump while climbing exits immediately to avoid floor-intersection stick cases.
	if Input.is_action_pressed("move_back") or Input.is_action_just_pressed("jump"):
		_abort_climb("manual detach")
		return

	if active_climb_rv is RigidBody3D:
		if (active_climb_rv as RigidBody3D).angular_velocity.length() > CLIMB_MAX_RV_ANGULAR_SPEED:
			_abort_climb("rv angular speed too high")
			return

	var rv_up := active_climb_rv.global_transform.basis.y.normalized()
	if Input.is_action_pressed("move_forward") and ClimbMath.try_roof_transfer(self, body_collision_shape, active_climb_rv, active_wall_normal):
		_exit_climb_to_normal()
		released_carrier_velocity = Vector3.ZERO
		velocity = Vector3.DOWN * 0.1
		move_and_slide()
		rv_support.capture(self)
		return
	_apply_wall_outward_alignment(rv_up)
	var has_valid_wall_contact := false
	var pending_abort_lost_contact := false

	if climb_wall_probe and climb_wall_probe.is_colliding():
		var wall_node := climb_wall_probe.get_collider() as Node
		if _find_rv_ancestor(wall_node) == active_climb_rv:
			var hit_normal: Vector3 = climb_wall_probe.get_collision_normal().normalized()
			has_valid_wall_contact = true
			active_wall_normal = hit_normal

	if has_valid_wall_contact:
		climb_contact_grace_remaining = CLIMB_CONTACT_GRACE_TIME
	else:
		climb_contact_grace_remaining -= delta
		if climb_contact_grace_remaining <= 0.0:
			pending_abort_lost_contact = true

	var vertical_input := 0.0
	if Input.is_action_pressed("move_forward"):
		vertical_input += 1.0
	if Input.is_action_pressed("move_back"):
		vertical_input -= 1.0

	if vertical_input > 0.0:
		var desired_upward_distance := vertical_input * CLIMB_VERTICAL_SPEED * delta
		var allowed_upward_distance := _clamp_upward_climb_distance(rv_up, desired_upward_distance)
		if allowed_upward_distance < desired_upward_distance:
			_debug_climb_log(
				"climb_ceiling_block",
				"side=%s wanted=%.3f allowed=%.3f hit_dist=%.3f src=%s hit_node=%s hit_pos=%s" % [
					_debug_climb_side_label(active_climb_rv, active_wall_normal),
					desired_upward_distance,
					allowed_upward_distance,
					debug_last_ceiling_hit_distance,
					debug_last_ceiling_hit_source,
					debug_last_ceiling_hit_node,
					_debug_v3(debug_last_ceiling_hit_position)
				],
				true
			)
			_abort_climb("ceiling detected")
			return
		else:
			vertical_input *= allowed_upward_distance / desired_upward_distance

	var horizontal_input := 0.0
	if Input.is_action_pressed("move_right"):
		horizontal_input += 1.0
	if Input.is_action_pressed("move_left"):
		horizontal_input -= 1.0

	var motion := _build_climb_motion(rv_up, active_wall_normal, vertical_input, horizontal_input, delta)
	var collision := _move_with_climb_collision(motion)
	if collision and _find_rv_ancestor(collision.get_collider()) == active_climb_rv:
		active_wall_normal = collision.get_normal().normalized()
	velocity = Vector3.ZERO

	if pending_abort_lost_contact:
		_abort_climb("lost wall contact")

func _abort_climb(reason: String = "") -> void:
	if CLIMB_DEBUG_LOG_ABORTS and not reason.is_empty():
		print("Climb aborted: ", reason)
	if debug_climb_messages and not reason.is_empty():
		_debug_climb_log(
			"abort",
			"reason=%s side=%s pos=%s wall_n=%s" % [
				reason,
				_debug_climb_side_label(active_climb_rv, active_wall_normal),
				_debug_v3(global_position),
				_debug_v3(active_wall_normal)
			],
			true
		)
	_exit_climb_to_normal()

func _exit_climb_to_normal() -> void:
	if locomotion_state == LocomotionState.CLIMBING:
		released_carrier_velocity = climb_carrier_velocity
		velocity = climb_carrier_velocity
	locomotion_state = LocomotionState.NORMAL
	active_climb_rv = null
	previous_climb_rv_transform = Transform3D.IDENTITY
	climb_contact_grace_remaining = 0.0
	climb_reenter_cooldown_remaining = CLIMB_REENTER_COOLDOWN
	active_wall_normal = Vector3.ZERO
	climb_carrier_velocity = Vector3.ZERO
	_sync_body_collision_to_locomotion()

func _physics_process(delta):
	if is_player_dead:
		return
	_sync_body_collision_to_locomotion()
	if is_instance_valid(seated_in):
		global_position = seated_in.global_position
		return
	if in_ui_mode:
		return

	if damage_cooldown > 0.0:
		damage_cooldown -= delta
	if climb_reenter_cooldown_remaining > 0.0:
		climb_reenter_cooldown_remaining = maxf(0.0, climb_reenter_cooldown_remaining - delta)

	match locomotion_state:
		LocomotionState.NORMAL:
			_process_normal_movement(delta)
			_try_start_climb()
		LocomotionState.CLIMBING:
			_apply_rv_delta_compensation()
			if locomotion_state == LocomotionState.CLIMBING:
				_process_climbing(delta)

	placement.update_ghost(self)



func take_damage(amount: float):
	if is_player_dead: return
	if damage_cooldown > 0.0: return
	
	current_player_health -= amount
	damage_cooldown = 0.5  # Half second invincibility after hit
	
	print("Player took ", amount, " damage! HP: ", current_player_health, "/", max_player_health)
	
	# Screen flash effect
	_update_health_bar()
	
	if current_player_health <= 0.0:
		current_player_health = 0.0
		_player_die()

func _update_health_bar():
	if health_bar and health_bar.has_method("set_health"):
		health_bar.set_health(current_player_health, max_player_health)

func _player_die():
	if is_placing_equipment():
		placement.placing_equipment.cancel_placement()
		placement.placing_equipment = null
	is_player_dead = true
	print(">>> PLAYER DIED! <<<")
	# For now just respawn with full health after 2 seconds
	var tween = create_tween()
	tween.tween_interval(2.0)
	tween.tween_callback(_respawn)

func _respawn():
	is_player_dead = false
	current_player_health = max_player_health
	_update_health_bar()
	print("Player respawned!")

func refresh_inventory() -> void:
	_update_inventory_display()
	_equip_active_slot()
