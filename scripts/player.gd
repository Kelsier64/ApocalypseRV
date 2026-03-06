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

@onready var inventory_ui = $InventoryUI

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
			held_item_node.transform = Transform3D.IDENTITY

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.current = true
	_update_inventory_display()
	_equip_active_slot()

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

func _physics_process(delta):
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
	
