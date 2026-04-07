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
const CLIMB_TOP_MIN_DOT = 0.35
const CLIMB_CONTACT_GRACE_TIME = 0.28
const CLIMB_START_CEILING_CHECK_DISTANCE = 0.8
const CLIMB_MAX_RV_ANGULAR_SPEED = 2.4
const CLIMB_MAX_FRAME_DELTA = 1.5
const CLIMB_REENTER_COOLDOWN = 0.2
const CLIMB_WALL_ALIGN_OFFSET = 0.22
const CLIMB_WALL_MAX_OUTWARD_CORRECTION = 0.08
const MANTLE_DURATION = 0.22
const MANTLE_FORWARD_OFFSET = 0.18
const MANTLE_UP_OFFSET = 0.1
const MANTLE_MIN_TARGET_CLEARANCE = 1.25
const CLIMB_DEBUG_LOG_ABORTS = false
const MANTLE_ROOF_PROBE_UP = 2.2
const MANTLE_ROOF_PROBE_DOWN = 0.8
const PropScript = preload("res://props/interactable_item.gd")
const EquipmentScript = preload("res://equipment/equipment.gd")

@onready var camera = $Camera3D

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

const MAX_SLOTS = 6
var inventory: Array[Dictionary] = []
var has_large_item: bool = false
var active_slot_index: int = 0
var held_item_node: Node3D = null

# Equipment Placement
var placing_equipment: Node3D = null
var max_place_distance: float = 4.0
var can_place_equipment: bool = false
enum PlacementMode { SURFACE, UPRIGHT } # SURFACE: bottom_face sticks to surface, UPRIGHT: bottom stays down
var placement_mode: PlacementMode = PlacementMode.SURFACE

# UI State
var in_ui_mode: bool = false

# Locomotion
enum LocomotionState { NORMAL, CLIMBING, MANTLING }
var locomotion_state: LocomotionState = LocomotionState.NORMAL
var active_climb_rv: Node3D = null
var previous_climb_rv_transform: Transform3D = Transform3D.IDENTITY
var active_wall_normal: Vector3 = Vector3.ZERO
var climb_contact_grace_remaining: float = 0.0
var climb_reenter_cooldown_remaining: float = 0.0
var mantle_start_position: Vector3 = Vector3.ZERO
var mantle_target_position: Vector3 = Vector3.ZERO
var mantle_elapsed: float = 0.0

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

func add_item(item_name: String, is_large: bool, scene_path: String) -> bool:
	if is_large and has_large_item:
		print("You are already carrying a large item! Must drop it first.")
		return false
	if inventory.size() >= MAX_SLOTS:
		print("Inventory full!")
		return false
		
	inventory.append({"name": item_name, "is_large": is_large, "scene_path": scene_path})
	var added_index = inventory.size() - 1
	
	if is_large:
		has_large_item = true
		active_slot_index = added_index # Force select this new slot
		
	_update_inventory_display()
	
	# If the item we just added is in the slot we are currently looking at
	if active_slot_index == added_index:
		_equip_active_slot()
		
	return true

func _update_inventory_display():
	if inventory_ui and inventory_ui.has_method("update_slots"):
		inventory_ui.update_slots(inventory, active_slot_index)

func _set_active_slot(index: int):
	# If we are currently holding a large item, we CANNOT switch away from it.
	if active_slot_index >= 0 and active_slot_index < inventory.size():
		if inventory[active_slot_index].get("is_large", false) and index != active_slot_index:
			print("You must drop the large item before switching slots!")
			return
			
	if active_slot_index != index:
		active_slot_index = index
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
		
	if active_slot_index < inventory.size() and active_slot_index >= 0:
		var item_data = inventory[active_slot_index]
		var scene: PackedScene = load(item_data["scene_path"])
		if scene:
			held_item_node = scene.instantiate()
			# Disable physics so it's just visual while held
			if held_item_node is RigidBody3D:
				held_item_node.freeze = true
				held_item_node.collision_layer = 0
				held_item_node.collision_mask = 0
				
			hand_marker.add_child(held_item_node)
			
			# Apply visual holding offsets if it's our new Prop class
			if held_item_node is PropScript:
				held_item_node.position = held_item_node.hold_position
				held_item_node.rotation_degrees = held_item_node.hold_rotation
				held_item_node.scale = held_item_node.hold_scale
			else:
				held_item_node.transform = Transform3D.IDENTITY

func _ready():
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
	add_to_group("player")
	current_player_health = max_player_health
	_update_health_bar()

func is_placing_equipment() -> bool:
	return placing_equipment != null

func get_active_item_name() -> String:
	if active_slot_index >= 0 and active_slot_index < inventory.size():
		return inventory[active_slot_index].get("name", "")
	return ""

func consume_active_item() -> void:
	if active_slot_index < 0 or active_slot_index >= inventory.size():
		return
	var item_data: Dictionary = inventory[active_slot_index]
	if item_data.get("is_large", false):
		has_large_item = false
	inventory.remove_at(active_slot_index)
	if active_slot_index >= inventory.size():
		active_slot_index = max(0, inventory.size() - 1)
	_update_inventory_display()
	_equip_active_slot()

func enter_equipment_placement(equip: Node3D):
	placing_equipment = equip
	placement_mode = PlacementMode.SURFACE

func enter_ui_mode():
	in_ui_mode = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
func exit_ui_mode():
	in_ui_mode = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func drop_item():
	if active_slot_index >= 0 and active_slot_index < inventory.size():
		var item_data = inventory[active_slot_index]
		
		# Spawn it back into the world
		var scene: PackedScene = load(item_data["scene_path"])
		if scene:
			var dropped_item = scene.instantiate()
			# Add to the root node (usually the World scene)
			get_tree().current_scene.add_child(dropped_item)
			
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
			
		# Update inventory state
		if item_data.get("is_large", false):
			has_large_item = false
			
		inventory.remove_at(active_slot_index)
		
		# Clamp active slot index if we dropped the last item
		if active_slot_index >= inventory.size():
			active_slot_index = max(0, inventory.size() - 1)
			
		_update_inventory_display()
		_equip_active_slot()

func _unhandled_input(event):
	if in_ui_mode: return
	
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
			_set_active_slot((active_slot_index - 1 + MAX_SLOTS) % MAX_SLOTS)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_active_slot((active_slot_index + 1) % MAX_SLOTS)
			
	# Number keys to change slots
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_6:
			_set_active_slot(event.physical_keycode - KEY_1)
			
	# Drop item
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.physical_keycode == KEY_G:
			drop_item()
			
	# Equipment Placement confirmation
	if placing_equipment:
		if event is InputEventKey and event.is_pressed() and not event.is_echo():
			if event.physical_keycode == KEY_R:
				if placement_mode == PlacementMode.SURFACE:
					placement_mode = PlacementMode.UPRIGHT
				else:
					placement_mode = PlacementMode.SURFACE
		if event is InputEventMouseButton and event.is_pressed():
			if event.button_index == MOUSE_BUTTON_LEFT and can_place_equipment:
				# We attempt to find what we are placing it ON to reparent it properly
				var space_state = get_world_3d().direct_space_state
				var from = camera.global_position
				var to = from + -camera.global_transform.basis.z * max_place_distance

				# Ignore ourselves and the equipment itself
				var query = PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self.get_rid(), placing_equipment.get_rid()])
				var result = space_state.intersect_ray(query)

				# Walk up from the collider to find the RV chassis instead of parenting
				# to whatever we hit (which could be another wall panel)
				var new_parent = null
				if result and result.collider is Node3D:
					var candidate: Node = result.collider
					while candidate != null:
						if candidate is VehicleBody3D or candidate.is_in_group("rv"):
							new_parent = candidate
							break
						candidate = candidate.get_parent()
					if new_parent == null:
						new_parent = result.collider
				else:
					new_parent = get_tree().current_scene

				placing_equipment.confirm_placement(placing_equipment.global_transform, new_parent)
				placing_equipment = null
				
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				placing_equipment.cancel_placement()
				placing_equipment = null

func _is_rv_wall_normal(hit_normal: Vector3, rv_up: Vector3 = Vector3.UP) -> bool:
	var n := hit_normal.normalized()
	var up := rv_up.normalized()
	var d := absf(n.dot(up))
	return d >= CLIMB_WALL_MIN_DOT and d <= CLIMB_WALL_MAX_DOT

func _is_valid_climb_hit_height(local_hit_y: float) -> bool:
	return local_hit_y >= CLIMB_MIN_HIT_Y and local_hit_y <= CLIMB_MAX_HIT_Y

func _can_begin_climb(jump_pressed: bool, w_pressed: bool, is_rv_hit: bool, wall_normal_ok: bool, hit_height_ok: bool) -> bool:
	return w_pressed and is_rv_hit and wall_normal_ok and hit_height_ok

func _can_start_mantle(top_surface_ok: bool, stand_clearance_ok: bool, forward_clear_ok: bool) -> bool:
	return top_surface_ok and stand_clearance_ok and forward_clear_ok

func _should_disable_body_collision_for_locomotion(state: int) -> bool:
	return state == LocomotionState.CLIMBING or state == LocomotionState.MANTLING

func _sync_body_collision_to_locomotion() -> void:
	if body_collision_shape == null:
		return
	body_collision_shape.disabled = _should_disable_body_collision_for_locomotion(int(locomotion_state))

func _compute_rv_position_delta(prev_rv_transform: Transform3D, next_rv_transform: Transform3D) -> Vector3:
	return next_rv_transform.origin - prev_rv_transform.origin

func _sanitize_velocity_after_climb(v: Vector3) -> Vector3:
	var out := v
	if out.y > CLIMB_EXIT_MAX_UP_VELOCITY:
		out.y = 0.0
	return out

func _compute_mantle_target(top_point: Vector3, rv_up: Vector3, cam_forward: Vector3) -> Vector3:
	# Keep a deterministic minimum so top-out does not regress when capsule setup changes.
	var clearance_up := maxf(MANTLE_MIN_TARGET_CLEARANCE, MANTLE_UP_OFFSET + _get_stand_origin_offset_up())
	var stand_base: Vector3 = top_point + rv_up * clearance_up
	return stand_base + cam_forward * MANTLE_FORWARD_OFFSET

func _get_stand_origin_offset_up() -> float:
	if body_collision_shape and body_collision_shape.shape is CapsuleShape3D:
		var capsule := body_collision_shape.shape as CapsuleShape3D
		var half_extent := capsule.height * 0.5 + capsule.radius
		var center_y: float = float(body_collision_shape.position.y)
		return maxf(0.08, half_extent - center_y + 0.03)
	return 0.15

func _build_climb_motion(rv_up: Vector3, wall_normal: Vector3, vertical_input: float, horizontal_input: float, delta: float) -> Vector3:
	var wall_tangent := rv_up.cross(wall_normal).normalized()
	if wall_tangent.length_squared() < 0.001:
		wall_tangent = transform.basis.x.normalized()

	var motion := (rv_up * vertical_input * CLIMB_VERTICAL_SPEED)
	motion += wall_tangent * horizontal_input * CLIMB_SIDE_SPEED
	motion += (-wall_normal) * CLIMB_WALL_STICK_SPEED
	var inward_mag := motion.dot(-wall_normal)
	if inward_mag > 0.0:
		motion += wall_normal * inward_mag
	motion *= delta
	if motion.length() > CLIMB_MAX_FRAME_DELTA:
		motion = motion.normalized() * CLIMB_MAX_FRAME_DELTA
	return motion

func _clamp_upward_climb_distance(rv_up: Vector3, desired_upward_distance: float) -> float:
	if desired_upward_distance <= 0.0:
		return 0.0

	var from := global_position + rv_up * 0.2
	var to := from + rv_up * (desired_upward_distance + 0.8)
	var min_hit_distance := INF

	if climb_upward_probe != null:
		var local_from := to_local(from)
		var local_to := to_local(to)
		climb_upward_probe.position = local_from
		climb_upward_probe.target_position = local_to - local_from
		climb_upward_probe.force_raycast_update()
		if climb_upward_probe.is_colliding():
			var probe_hit_position: Vector3 = climb_upward_probe.get_collision_point()
			min_hit_distance = minf(min_hit_distance, from.distance_to(probe_hit_position))

	# Fallback query improves robustness when RayCast3D node config/layers miss a collider.
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self.get_rid()])
	query.hit_from_inside = true
	var hit := space_state.intersect_ray(query)
	if hit:
		var hit_position: Vector3 = hit.get("position", from) as Vector3
		min_hit_distance = minf(min_hit_distance, from.distance_to(hit_position))

	if min_hit_distance == INF:
		return desired_upward_distance

	# Keep a small safety gap so we stop before interpenetrating the ceiling surface.
	var safe_distance := maxf(0.0, min_hit_distance - 0.05)
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

func _probe_roof_from_above(rv_up: Vector3, cam_forward: Vector3) -> Dictionary:
	if active_climb_rv == null:
		return {}

	var space_state := get_world_3d().direct_space_state
	var from := global_position + rv_up * MANTLE_ROOF_PROBE_UP + cam_forward * (MANTLE_FORWARD_OFFSET + 0.35)
	var to := global_position - rv_up * MANTLE_ROOF_PROBE_DOWN + cam_forward * (MANTLE_FORWARD_OFFSET + 0.35)
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self.get_rid()])
	var hit := space_state.intersect_ray(query)
	if hit:
		var hit_node := hit.collider as Node
		if _find_rv_ancestor(hit_node) == active_climb_rv:
			return {
				"position": hit.position,
				"normal": hit.normal
			}
	return {}

func _find_rv_ancestor(node: Node) -> Node3D:
	var current := node
	while current != null:
		if current is Node3D and current.is_in_group("rv"):
			return current as Node3D
		current = current.get_parent()
	return null

func _process_normal_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1
	if Input.is_physical_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.y += 1

	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()

	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()

func _try_start_climb() -> void:
	if locomotion_state != LocomotionState.NORMAL:
		return
	if climb_reenter_cooldown_remaining > 0.0:
		return
	if not Input.is_physical_key_pressed(KEY_W):
		return
	if climb_wall_probe == null or not climb_wall_probe.is_colliding():
		return

	var hit_node := climb_wall_probe.get_collider() as Node
	var rv := _find_rv_ancestor(hit_node)
	if rv == null:
		return

	var hit_normal: Vector3 = climb_wall_probe.get_collision_normal()
	var hit_point: Vector3 = climb_wall_probe.get_collision_point()
	var local_hit_y: float = to_local(hit_point).y
	var rv_up: Vector3 = rv.global_transform.basis.y.normalized()
	if _clamp_upward_climb_distance(rv_up, CLIMB_START_CEILING_CHECK_DISTANCE) < CLIMB_START_CEILING_CHECK_DISTANCE:
		# Ceiling detected overhead: block entering climb state.
		return
	var wall_normal_ok := _is_rv_wall_normal(hit_normal, rv_up)
	var hit_height_ok := _is_valid_climb_hit_height(local_hit_y)
	if not _can_begin_climb(false, true, true, wall_normal_ok, hit_height_ok):
		return

	locomotion_state = LocomotionState.CLIMBING
	active_climb_rv = rv
	previous_climb_rv_transform = rv.global_transform
	active_wall_normal = hit_normal.normalized()
	climb_contact_grace_remaining = CLIMB_CONTACT_GRACE_TIME
	velocity = Vector3.ZERO

func _apply_rv_delta_compensation() -> void:
	if active_climb_rv == null or not is_instance_valid(active_climb_rv):
		return
	var next_transform := active_climb_rv.global_transform
	var delta_pos := _compute_rv_position_delta(previous_climb_rv_transform, next_transform)
	if delta_pos.length() > CLIMB_MAX_FRAME_DELTA:
		delta_pos = delta_pos.normalized() * CLIMB_MAX_FRAME_DELTA
	var collision := _move_with_climb_collision(delta_pos)
	if collision and _find_rv_ancestor(collision.get_collider()) == active_climb_rv:
		active_wall_normal = collision.get_normal().normalized()
	previous_climb_rv_transform = next_transform

func _query_mantle_target() -> Dictionary:
	if active_climb_rv == null:
		return {"ok": false}

	var rv_up: Vector3 = active_climb_rv.global_transform.basis.y.normalized()
	var cam_forward: Vector3 = -camera.global_transform.basis.z
	cam_forward = (cam_forward - rv_up * cam_forward.dot(rv_up)).normalized()
	if cam_forward.length_squared() < 0.001:
		cam_forward = (-active_wall_normal).normalized()

	var top_hit: Dictionary = _probe_roof_from_above(rv_up, cam_forward)
	if top_hit.is_empty():
		return {"ok": false}

	var top_normal: Vector3 = (top_hit.get("normal", rv_up) as Vector3).normalized()
	var top_surface_ok: bool = top_normal.dot(rv_up) >= CLIMB_TOP_MIN_DOT
	var top_point: Vector3 = top_hit.get("position", global_position) as Vector3
	var target: Vector3 = _compute_mantle_target(top_point, rv_up, cam_forward)

	var stand_clearance_ok: bool = _is_stand_position_clear(target)

	var space_state := get_world_3d().direct_space_state
	var forward_from: Vector3 = target + rv_up * 0.2
	var forward_to: Vector3 = forward_from + cam_forward * 0.35
	var forward_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(forward_from, forward_to, 0xFFFFFFFF, [self.get_rid()])
	var forward_hit := space_state.intersect_ray(forward_query)
	var forward_clear_ok := true
	if forward_hit:
		var f_node := forward_hit.collider as Node
		if _find_rv_ancestor(f_node) != active_climb_rv:
			forward_clear_ok = false

	return {
		"ok": _can_start_mantle(top_surface_ok, stand_clearance_ok, forward_clear_ok),
		"target": target
	}

func _is_stand_position_clear(candidate_position: Vector3) -> bool:
	if active_climb_rv == null:
		return true

	var rv_up := active_climb_rv.global_transform.basis.y.normalized()
	var space_state := get_world_3d().direct_space_state

	# 1) Need support surface under target feet.
	var support_from := candidate_position + rv_up * 0.25
	var support_depth := maxf(MANTLE_MIN_TARGET_CLEARANCE, MANTLE_UP_OFFSET + _get_stand_origin_offset_up()) + 0.2
	var support_to := candidate_position - rv_up * support_depth
	var support_query := PhysicsRayQueryParameters3D.create(support_from, support_to, 0xFFFFFFFF, [self.get_rid()])
	var support_hit := space_state.intersect_ray(support_query)
	if not support_hit:
		return false
	var support_node := support_hit.collider as Node
	if _find_rv_ancestor(support_node) != active_climb_rv:
		return false
	var support_normal := (support_hit.normal as Vector3).normalized()
	if support_normal.dot(rv_up) < CLIMB_TOP_MIN_DOT:
		return false

	# 2) Need free headroom at target.
	var head_from := candidate_position + rv_up * 0.25
	var head_to := candidate_position + rv_up * 1.9
	var head_query := PhysicsRayQueryParameters3D.create(head_from, head_to, 0xFFFFFFFF, [self.get_rid()])
	var head_hit := space_state.intersect_ray(head_query)
	if head_hit:
		return false

	return true

func _begin_mantle(target: Vector3) -> void:
	if locomotion_state != LocomotionState.CLIMBING:
		return
	locomotion_state = LocomotionState.MANTLING
	mantle_start_position = global_position
	mantle_target_position = target
	mantle_elapsed = 0.0
	velocity = Vector3.ZERO

func _process_climbing(delta: float) -> void:
	if active_climb_rv == null or not is_instance_valid(active_climb_rv):
		_abort_climb("rv invalid")
		return

	# Manual detach: pressing S or Space while climbing exits immediately to avoid floor-intersection stick cases.
	if Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("ui_accept"):
		_abort_climb("manual detach")
		return

	if active_climb_rv is RigidBody3D:
		if (active_climb_rv as RigidBody3D).angular_velocity.length() > CLIMB_MAX_RV_ANGULAR_SPEED:
			_abort_climb("rv angular speed too high")
			return

	var rv_up := active_climb_rv.global_transform.basis.y.normalized()
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
		var mantle_result_on_loss := _query_mantle_target()
		if mantle_result_on_loss.get("ok", false):
			_begin_mantle(mantle_result_on_loss.get("target", global_position))
			return
		climb_contact_grace_remaining -= delta
		if climb_contact_grace_remaining <= 0.0:
			pending_abort_lost_contact = true

	var vertical_input := 0.0
	if Input.is_physical_key_pressed(KEY_W):
		vertical_input += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		vertical_input -= 1.0

	if vertical_input > 0.0:
		var desired_upward_distance := vertical_input * CLIMB_VERTICAL_SPEED * delta
		var allowed_upward_distance := _clamp_upward_climb_distance(rv_up, desired_upward_distance)
		if allowed_upward_distance < desired_upward_distance:
			_abort_climb("ceiling detected")
			return
		else:
			vertical_input *= allowed_upward_distance / desired_upward_distance

	var horizontal_input := 0.0
	if Input.is_physical_key_pressed(KEY_D):
		horizontal_input += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		horizontal_input -= 1.0

	var motion := _build_climb_motion(rv_up, active_wall_normal, vertical_input, horizontal_input, delta)
	var collision := _move_with_climb_collision(motion)
	if collision and _find_rv_ancestor(collision.get_collider()) == active_climb_rv:
		active_wall_normal = collision.get_normal().normalized()
	velocity = Vector3.ZERO

	var mantle_result := _query_mantle_target()
	if mantle_result.get("ok", false):
		_begin_mantle(mantle_result.get("target", global_position))
		return

	if pending_abort_lost_contact:
		var final_mantle_result := _query_mantle_target()
		if final_mantle_result.get("ok", false):
			_begin_mantle(final_mantle_result.get("target", global_position))
			return
		_abort_climb("lost wall contact")
func _process_mantle(delta: float) -> void:
	if active_climb_rv == null or not is_instance_valid(active_climb_rv):
		_abort_climb("rv invalid")
		return

	mantle_elapsed += delta
	var t := clampf(mantle_elapsed / MANTLE_DURATION, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var target_position := mantle_start_position.lerp(mantle_target_position, eased)
	_move_with_climb_collision(target_position - global_position)
	velocity = Vector3.ZERO

	if t >= 1.0:
		if not _is_stand_position_clear(mantle_target_position):
			global_position = mantle_start_position
			_abort_climb("mantle stand position blocked")
			return
		_abort_climb("mantle complete")

func _abort_climb(reason: String = "") -> void:
	if CLIMB_DEBUG_LOG_ABORTS and not reason.is_empty():
		print("Climb aborted: ", reason)
	_exit_climb_to_normal()

func _exit_climb_to_normal() -> void:
	locomotion_state = LocomotionState.NORMAL
	active_climb_rv = null
	previous_climb_rv_transform = Transform3D.IDENTITY
	climb_contact_grace_remaining = 0.0
	climb_reenter_cooldown_remaining = CLIMB_REENTER_COOLDOWN
	active_wall_normal = Vector3.ZERO
	velocity = _sanitize_velocity_after_climb(velocity)

func _physics_process(delta):
	_sync_body_collision_to_locomotion()
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
			_process_climbing(delta)
		LocomotionState.MANTLING:
			_apply_rv_delta_compensation()
			_process_mantle(delta)

	_update_equipment_placement_ghost()

func _update_equipment_placement_ghost() -> void:
	if not placing_equipment:
		return

	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	var to = from + -camera.global_transform.basis.z * max_place_distance

	# Ignore ourselves and the equipment
	var query = PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self.get_rid(), placing_equipment.get_rid()])
	var result = space_state.intersect_ray(query)

	if result:
		can_place_equipment = true
		placing_equipment.visible = true

		var equip = placing_equipment
		var normal = result.normal
		var base_basis: Basis

		# Use RV's local up if placing on RV, so equipment aligns with the RV when it's tilted
		var up_ref: Vector3 = Vector3.UP
		var hit_node: Node = result.collider
		while hit_node != null:
			if hit_node.is_in_group("rv"):
				up_ref = (hit_node as Node3D).global_transform.basis.y.normalized()
				break
			hit_node = hit_node.get_parent()

		if placement_mode == PlacementMode.SURFACE:
			# Mode 1: bottom_face sticks to the placement surface
			if abs(normal.dot(up_ref)) > 0.5:
				var cam_dir = -camera.global_transform.basis.z
				cam_dir = (cam_dir - normal * cam_dir.dot(normal)).normalized()
				if cam_dir.length_squared() < 0.001:
					cam_dir = Vector3.FORWARD.cross(normal).normalized()
					if cam_dir.length_squared() < 0.001:
						cam_dir = Vector3.RIGHT.cross(normal).normalized()
				base_basis = Basis.looking_at(cam_dir, normal)
			else:
				var tangent = normal.cross(up_ref).normalized()
				if tangent.length_squared() < 0.001:
					tangent = Vector3.FORWARD
				base_basis = Basis.looking_at(tangent, normal)

			if equip and equip is EquipmentScript:
				base_basis = base_basis * equip.get_bottom_face_correction()
		else:
			# Mode 2: bottom faces up_ref-down, closest face contacts surface
			var cam_dir = -camera.global_transform.basis.z
			cam_dir = (cam_dir - up_ref * cam_dir.dot(up_ref)).normalized()
			if cam_dir.length_squared() < 0.001:
				# Camera pointing along up_ref axis - use RV's forward as fallback
				var rv_forward := -up_ref.cross(Vector3.RIGHT).normalized()
				if rv_forward.length_squared() < 0.001:
					rv_forward = Vector3.FORWARD
				cam_dir = rv_forward

			if abs(normal.dot(up_ref)) > 0.5:
				# Horizontal surface: standard upright, facing camera direction
				base_basis = Basis.looking_at(cam_dir, up_ref)
			else:
				# Vertical surface: upright, back face against wall
				base_basis = Basis.looking_at(normal, up_ref)

		placing_equipment.global_transform.basis = base_basis

		# Auto-calculate offset from collision shape so the contact face sits flush
		var offset: float = 0.0
		if equip and equip is EquipmentScript:
			var local_into_surface: Vector3 = base_basis.inverse() * (-normal)
			var half: Vector3 = equip.get_half_extents()
			offset = abs(local_into_surface.x) * half.x + abs(local_into_surface.y) * half.y + abs(local_into_surface.z) * half.z

		placing_equipment.global_position = result.position + (normal * offset)
	else:
		can_place_equipment = false
		# Hide it when looking at the sky so they know they can't place
		placing_equipment.visible = false

# --- HEALTH SYSTEM ---
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
