extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

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

# UI State
var in_ui_mode: bool = false

# Health System
var max_player_health: float = 100.0
var current_player_health: float = 100.0
var damage_cooldown: float = 0.0
var is_player_dead: bool = false

@onready var inventory_ui = $InventoryUI
@onready var health_bar = $HealthBarUI

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
			if held_item_node is Prop:
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
	add_to_group("player")
	current_player_health = max_player_health
	_update_health_bar()

func is_placing_equipment() -> bool:
	return placing_equipment != null

func enter_equipment_placement(equip: Node3D):
	placing_equipment = equip

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
		if event is InputEventMouseButton and event.is_pressed():
			if event.button_index == MOUSE_BUTTON_LEFT and can_place_equipment:
				# We attempt to find what we are placing it ON to reparent it properly
				var space_state = get_world_3d().direct_space_state
				var from = camera.global_position
				var to = from + -camera.global_transform.basis.z * max_place_distance
				
				# Ignore ourselves and the equipment itself
				var query = PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self.get_rid(), placing_equipment.get_rid()])
				var result = space_state.intersect_ray(query)
				
				var new_parent = null
				if result:
					if result.collider is Node3D:
						new_parent = result.collider
				else:
					new_parent = get_tree().current_scene
					
				placing_equipment.confirm_placement(placing_equipment.global_transform, new_parent)
				placing_equipment = null
				
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				placing_equipment.cancel_placement()
				placing_equipment = null

func _physics_process(delta):
	if in_ui_mode: return
	
	# Damage cooldown
	if damage_cooldown > 0.0:
		damage_cooldown -= delta
	
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var input_dir = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
	if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
	
	if input_dir.length_squared() > 0:
		input_dir = input_dir.normalized()
		
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	# move_and_slide handles platform position
	move_and_slide()
	
	# Handle Equipment Placement Ghost
	if placing_equipment:
		var space_state = get_world_3d().direct_space_state
		var from = camera.global_position
		var to = from + -camera.global_transform.basis.z * max_place_distance
		
		# Ignore ourselves and the equipment
		var query = PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self.get_rid(), placing_equipment.get_rid()])
		var result = space_state.intersect_ray(query)
		
		if result:
			can_place_equipment = true
			placing_equipment.visible = true
			
			var equip = placing_equipment as Equipment
			var offset = equip.placement_offset if equip else 0.0
			# Align to surface normal first so the offset is applied in the correct local direction relative to the normal
			var normal = result.normal
			
			# If the surface is mostly horizontal (within 60 degrees of UP or DOWN)
			if abs(normal.dot(Vector3.UP)) > 0.5: 
				# Project the camera's looking direction onto the surface plane
				var cam_dir = -camera.global_transform.basis.z
				
				# Remove the component of cam_dir that is parallel to the normal
				cam_dir = (cam_dir - normal * cam_dir.dot(normal)).normalized()
				
				# Fallback if pointing exactly down the normal (rare but possible)
				if cam_dir.length_squared() < 0.001:
					cam_dir = Vector3.FORWARD.cross(normal).normalized()
					if cam_dir.length_squared() < 0.001:
						cam_dir = Vector3.RIGHT.cross(normal).normalized()
				
				# Use looking_at with the surface normal as UP
				placing_equipment.global_transform.basis = Basis.looking_at(cam_dir, normal)
			else:
				var x_axis = normal.cross(Vector3.UP).normalized()
				if x_axis.length_squared() < 0.001:
					x_axis = normal.cross(Vector3.FORWARD).normalized()
				var z_axis = x_axis.cross(normal).normalized()
				placing_equipment.global_transform.basis = Basis(x_axis, normal, z_axis)
				
			# Place at hit point + normal * offset
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
