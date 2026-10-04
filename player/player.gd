extends CharacterBody3D

const SPEED = 5.0
const SPRINT_SPEED = 8.0
const CRAWL_ONE_LEG_SPEED := 0.8
const CRAWL_NO_LEGS_SPEED := 0.55
const CRAWL_ONE_ARM_SPEED := 0.35
const CRAWL_RADIUS := 0.24
const CRAWL_ONE_LEG_LENGTH := 1.4
const CRAWL_NO_LEGS_LENGTH := 0.95
const JUMP_VELOCITY = 4.5
const MAX_STAMINA = 100.0
const SPRINT_STAMINA_PER_SECOND = 20.0
const JUMP_STAMINA_COST = 15.0
const STAMINA_RECOVERY_PER_SECOND = 18.0
const STAMINA_RECOVERY_DELAY = 1.0
const STAMINA_EXHAUSTION_RECOVERY = 20.0
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
const LARGE_ITEM_CLIMB_MESSAGE := "手持大型物品時無法攀爬，請先丟棄、消耗或存入"
const PropScript = preload("res://props/interactable_item.gd")

@onready var camera = $Camera3D
@onready var game_settings = get_node("/root/GameSettings")

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

const MAX_SLOTS = PlayerInventory.MAX_SLOTS
var inventory := PlayerInventory.new()
var body_state := PlayerBodyState.new()
var standing_collision_shape: Shape3D
var standing_collision_transform := Transform3D.IDENTITY
var placement := EquipmentPlacement.new()
var held_item_node: Node3D = null
var _flashlight_display_signature := ""

@export_group("Debug")
@export var debug_climb_messages: bool = false
@export var debug_climb_message_interval: float = 0.35

# UI State
var in_ui_mode: bool = false
var settings_open: bool = false
# Closing settings waits for held controls to be released before gameplay resumes.
const SETTINGS_GAMEPLAY_KEYS = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_SPACE, KEY_E, KEY_F, KEY_H, KEY_B, KEY_L, KEY_Z, KEY_X, KEY_C, KEY_R, KEY_T, KEY_Q, KEY_V, KEY_G, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
const SETTINGS_GAMEPLAY_ACTIONS = [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"jump", &"interact", &"place_equipment", &"toggle_flashlight", &"drop_item", &"toggle_placement_mode", &"hotbar_1", &"hotbar_2", &"hotbar_3", &"hotbar_4", &"hotbar_5", &"hotbar_6"]
var _settings_release_keys: Array[int] = []
var _settings_release_buttons: Array[int] = []
var _settings_release_actions: Array[StringName] = []

# Top-level mode. The individual flags (in_ui_mode, placement state,
# seated_in, is_player_dead) remain the storage, but every transition must go
# through the enter_/exit_ helpers below so exclusivity is enforced in one
# place instead of ad-hoc at each call site.
signal grab_started
signal body_state_changed
var grab_control: Node
var ragdoll_control: Node
var death_velocity := Vector3.ZERO
enum PlayerMode { NORMAL, PLACING, UI, SEATED, DEAD, GRABBED }
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
var _large_item_climb_feedback_shown := false
var crawl_transition_remaining: float = 0.0
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

# Stamina is spent only by normal movement, not RV climbing or driving.
var current_stamina: float = MAX_STAMINA
var stamina_recovery_delay_remaining: float = 0.0
var stamina_exhausted: bool = false

@onready var inventory_ui = $InventoryUI
@onready var health_bar = $HealthBarUI
@onready var body_collision_shape = $CollisionShape3D
@onready var climb_wall_probe = $ClimbWallProbe
@onready var climb_upward_probe = $ClimbUpwardProbe

func add_prop_item(prop: Prop, path: String) -> bool:
	if not can_use_hands(2 if prop.is_large else 1): return false
	return add_item(prop.item_name, prop.is_large, path, prop.capture_item_state())

func add_item(item_name: String, is_large: bool, scene_path: String, state: Dictionary = {}) -> bool:
	var previous_slot := inventory.active_slot
	if not inventory.add_item(item_name, is_large, scene_path, state):
		return false
	_abort_climb_if_holding_large_item()
	if inventory.active_slot != previous_slot:
		_set_flashlight_off_at(previous_slot)
	_update_inventory_display()
	if inventory.active_slot == inventory.items.size() - 1:
		_equip_active_slot()
	return true

func _update_inventory_display():
	if inventory_ui and inventory_ui.has_method("update_slots"):
		inventory_ui.update_slots(inventory.items, inventory.active_slot, get_player_mode() == PlayerMode.NORMAL and can_use_hands())

func _active_flashlight_state() -> Dictionary:
	var item := inventory.active_item()
	if item.get("scene_path", "") != "res://props/flashlight.tscn": return {}
	return item.get("state", {}).get("flashlight", {})

func _set_flashlight_off_at(index: int) -> void:
	if index < 0 or index >= inventory.items.size(): return
	var item: Dictionary = inventory.items[index]
	if item.get("scene_path", "") != "res://props/flashlight.tscn": return
	var state: Dictionary = item.get("state", {})
	var flashlight: Dictionary = state.get("flashlight", {})
	flashlight["on"] = false
	state["flashlight"] = flashlight
	item["state"] = state
	inventory.items[index] = item

func _toggle_flashlight() -> void:
	if is_gameplay_input_blocked() or get_player_mode() != PlayerMode.NORMAL or not can_use_hands(): return
	if not held_item_node is Flashlight: return
	var item := inventory.active_item()
	if item.get("scene_path", "") != "res://props/flashlight.tscn": return
	var state: Dictionary = item.get("state", {})
	var flashlight: Dictionary = state.get("flashlight", {})
	if float(flashlight.get("charge", 0.0)) <= 0.0: return
	flashlight["on"] = not bool(flashlight.get("on", false))
	state["flashlight"] = flashlight
	item["state"] = state
	inventory.items[inventory.active_slot] = item
	_advance_flashlight(0.0)

func _advance_flashlight(delta: float) -> void:
	var flashlight: Dictionary = _active_flashlight_state()
	var mode_allows_light: bool = can_use_hands() and (get_player_mode() == PlayerMode.NORMAL or (get_player_mode() == PlayerMode.GRABBED and grab_control.keep_flashlight))
	var active := mode_allows_light and not flashlight.is_empty() and bool(flashlight.get("on", false)) and float(flashlight.get("charge", 0.0)) > 0.0
	var held := held_item_node as Flashlight
	if held:
		held.switched_on = active
		held.charge = float(flashlight.get("charge", 0.0)) if not flashlight.is_empty() else 0.0
		held.set_held_active(active)
		active = active and (held.get_node_or_null("Beam") as SpotLight3D).is_visible_in_tree()
	else:
		active = false
	if active and delta > 0.0:
		var item := inventory.active_item()
		var state: Dictionary = item.get("state", {})
		flashlight["charge"] = maxf(0.0, float(flashlight.charge) - delta * Flashlight.FULL_CHARGE / Flashlight.DRAIN_SECONDS)
		if flashlight.charge <= 0.0:
			flashlight["on"] = false
			held.switched_on = false
			held.set_held_active(false)
		state["flashlight"] = flashlight
		item["state"] = state
		inventory.items[inventory.active_slot] = item
	var signature := "%s:%d:%d" % [get_player_mode() == PlayerMode.NORMAL, ceili(float(flashlight.get("charge", 0.0))), int(bool(flashlight.get("on", false)))] if not flashlight.is_empty() else ""
	if signature != _flashlight_display_signature:
		_flashlight_display_signature = signature
		_update_inventory_display()

func _set_active_slot(index: int) -> void:
	if is_grabbed() or is_gameplay_input_blocked(): return
	var previous := inventory.active_slot
	# A now unusable large item stays in the bag but must not lock slot selection.
	var changed := false
	if not can_use_hands(2) and inventory.active_item().get("is_large", false):
		changed = index >= 0 and index < MAX_SLOTS and index != previous
		if changed: inventory.active_slot = index
	else:
		changed = inventory.select_slot(index)
	if changed:
		_abort_climb_if_holding_large_item()
		_set_flashlight_off_at(previous)
		_update_inventory_display()
		_equip_active_slot()
		_advance_flashlight(0.0)

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
	if not can_use_hands(2 if inventory.active_item().get("is_large", false) else 1): return
		
	if inventory.active_slot < inventory.items.size() and inventory.active_slot >= 0:
		var item_data = inventory.items[inventory.active_slot]
		var scene: PackedScene = load(item_data["scene_path"])
		if scene:
			held_item_node = scene.instantiate()
			_restore_prop_state(held_item_node, item_data)
			if held_item_node.has_method("set_held"): held_item_node.set_held(true)
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
	standing_collision_shape = body_collision_shape.shape.duplicate()
	standing_collision_transform = body_collision_shape.transform
	grab_control = preload("res://player/player_grab.gd").new()
	add_child(grab_control)
	grab_started.connect(close_settings)
	ragdoll_control = preload("res://player/player_ragdoll.gd").new()
	add_child(ragdoll_control)
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
	_update_stamina_bar()
	camera.fov = float(game_settings.get_setting(&"walk_fov"))
	game_settings.setting_changed.connect(_on_setting_changed)

func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"walk_fov": camera.fov = float(value)

func can_open_settings() -> bool:
	if in_ui_mode or is_player_dead or is_grabbed(): return false
	var world := get_tree().current_scene
	if world != null:
		var ready: Variant = world.get("play_ready")
		if ready is bool and not ready: return false
		var manager := world.get_node_or_null("PoiInstances")
		if manager != null and manager.get("busy") == true: return false
	var checkpoint := get_node_or_null("/root/Checkpoint")
	return checkpoint == null or checkpoint.get("loading") != true

func set_settings_open(value: bool) -> void:
	if settings_open == value: return
	if value:
		cancel_equipment_placement()
	settings_open = value
	if not value:
		_capture_settings_release_latch()
	var interaction := camera.get_node_or_null("InteractRay")
	if interaction != null and interaction.has_method("cancel_input_gestures"):
		interaction.cancel_input_gestures()

func close_settings() -> void:
	var menu := get_node_or_null("SettingsMenu")
	if menu != null and menu.has_method("close_menu"):
		menu.close_menu()
	# Lifecycle callers also clean up programmatic input gates when the menu
	# has already hidden or is not present in a small behavior fixture.
	set_settings_open(false)

func cancel_equipment_placement() -> void:
	placement.cancel(self)
	_advance_flashlight(0.0)

func _capture_settings_release_latch() -> void:
	_settings_release_keys.clear()
	_settings_release_buttons.clear()
	_settings_release_actions.clear()
	for key: int in SETTINGS_GAMEPLAY_KEYS:
		if Input.is_physical_key_pressed(key): _settings_release_keys.append(key)
	for button: int in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		if Input.is_mouse_button_pressed(button): _settings_release_buttons.append(button)
	for action: StringName in SETTINGS_GAMEPLAY_ACTIONS:
		if Input.is_action_pressed(action): _settings_release_actions.append(action)

func is_gameplay_input_blocked() -> bool:
	if settings_open: return true
	for index in range(_settings_release_keys.size() - 1, -1, -1):
		if not Input.is_physical_key_pressed(_settings_release_keys[index]): _settings_release_keys.remove_at(index)
	for index in range(_settings_release_buttons.size() - 1, -1, -1):
		if not Input.is_mouse_button_pressed(_settings_release_buttons[index]): _settings_release_buttons.remove_at(index)
	for index in range(_settings_release_actions.size() - 1, -1, -1):
		if not Input.is_action_pressed(_settings_release_actions[index]): _settings_release_actions.remove_at(index)
	return not _settings_release_keys.is_empty() or not _settings_release_buttons.is_empty() or not _settings_release_actions.is_empty()

func is_placing_equipment() -> bool:
	return is_instance_valid(placement.placing_equipment)

func get_active_item_name() -> String:
	if not can_use_hands(2 if inventory.active_item().get("is_large", false) else 1): return ""
	return inventory.active_item().get("name", "")

func consume_active_item() -> void:
	if is_grabbed(): return
	_set_flashlight_off_at(inventory.active_slot)
	if inventory.consume_active():
		_abort_climb_if_holding_large_item()
		_update_inventory_display()
		_equip_active_slot()

func get_player_mode() -> PlayerMode:
	if is_player_dead:
		return PlayerMode.DEAD
	if is_grabbed(): return PlayerMode.GRABBED
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
	if is_gameplay_input_blocked() or get_player_mode() != PlayerMode.NORMAL or not can_use_hands(2):
		return false
	placement.begin(equip)
	_advance_flashlight(0.0)
	return true

func enter_ui_mode() -> bool:
	close_settings()
	if get_player_mode() != PlayerMode.NORMAL:
		return false
	in_ui_mode = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_advance_flashlight(0.0)
	return true

func exit_ui_mode():
	in_ui_mode = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_advance_flashlight(0.0)

func complete_world_transition(at: Transform3D) -> void:
	close_settings()
	grab_control.clear_view_recovery()
	if is_instance_valid(held_item_node) and held_item_node is Flashlight:
		(held_item_node as Flashlight).set_held_active(false)
	if is_grabbed(): grab_control.end("world_transition")
	var restart_death: bool = is_instance_valid(ragdoll_control) and ragdoll_control.active
	if restart_death or ragdoll_control.following_detached_head: ragdoll_control.stop()
	global_transform = at
	velocity = Vector3.ZERO
	locomotion_state = LocomotionState.NORMAL
	active_climb_rv = null
	rv_support.clear()
	released_carrier_velocity = Vector3.ZERO
	climb_carrier_velocity = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.current = true
	reset_physics_interpolation()
	# Held articulated bodies belong to the destination World3D and grip frame.
	if is_instance_valid(held_item_node) and held_item_node.has_method("set_held"):
		_equip_active_slot()
	if restart_death:
		# A cancelled POI transition may return a dead actor to its home world.
		# Rebind physics at that location instead of keeping the old-space pose.
		death_velocity = Vector3.ZERO
		_begin_death_physics.call_deferred()

func restore_checkpoint_state(state: Dictionary) -> void:
	crawl_transition_remaining = 0.0
	body_state.restore(state.get("body", {}))
	inventory.items.assign(state.items.duplicate(true))
	inventory.active_slot = state.slot
	current_player_health = state.health
	current_stamina = clampf(float(state.get("stamina", MAX_STAMINA)), 0.0, MAX_STAMINA)
	stamina_recovery_delay_remaining = 0.0
	stamina_exhausted = bool(state.get("stamina_exhausted", current_stamina <= 0.0))
	complete_world_transition(state.transform)
	_apply_body_capabilities()
	refresh_inventory()
	_update_health_bar()
	_update_stamina_bar()
	if current_player_health <= 0.0: _player_die()

## Seat flow: the player owns its own state mutation; the seat only decides
## where the player reappears and which camera takes over.
func enter_seat_mode(seat: Node3D) -> bool:
	if is_gameplay_input_blocked() or get_player_mode() != PlayerMode.NORMAL or not can_drive():
		return false
	grab_control.clear_view_recovery()
	_exit_climb_to_normal()
	rv_support.clear()
	velocity = Vector3.ZERO
	released_carrier_velocity = Vector3.ZERO
	seated_in = seat
	_advance_flashlight(0.0)
	global_transform = seat.global_transform.orthonormalized()
	set_process_unhandled_input(false)
	body_collision_shape.disabled = true
	visible = true
	return true

func exit_seat_mode(exit_position: Vector3) -> void:
	if is_grabbed(): grab_control.end("seat_lost")
	grab_control.clear_view_recovery()
	if seated_in == null:
		return
	var rv := _find_rv_ancestor(seated_in)
	velocity = ClimbMath.point_velocity(rv, exit_position)
	released_carrier_velocity = velocity
	seated_in = null
	_advance_flashlight(0.0)
	set_physics_process(true)
	set_process_unhandled_input(true)
	body_collision_shape.disabled = false
	visible = true
	global_position = exit_position
	global_rotation = Vector3(0, global_rotation.y, 0)
	camera.current = true

func drop_item():
	if is_grabbed() or is_gameplay_input_blocked(): return
	if inventory.active_slot >= 0 and inventory.active_slot < inventory.items.size():
		_set_flashlight_off_at(inventory.active_slot)
		var item_data = inventory.items[inventory.active_slot]
		
		# Spawn it back into the world
		var corpse_frame := Transform3D.IDENTITY
		var dropping_corpse := is_instance_valid(held_item_node) and held_item_node is CorpseProp
		if dropping_corpse:
			item_data = item_data.duplicate(true)
			item_data.state = held_item_node.capture_item_state()
			corpse_frame = held_item_node.global_transform
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
			if dropping_corpse: drop_transform = corpse_frame
			dropped_item.global_transform = drop_transform
			
			# If it's a rigid body, give it a tiny toss forward
			if dropped_item is RigidBody3D:
				dropped_item.linear_velocity = -transform.basis.z * 3.0
				if dropping_corpse: dropped_item.linear_velocity += velocity
			
		consume_active_item()

func _restore_prop_state(node: Node, data: Dictionary) -> void:
	if node is Prop:
		node.item_name = data["name"]
		node.is_large = data["is_large"]
		node.restore_item_state(data.get("state", {}))

func _unhandled_input(event):
	if in_ui_mode or is_player_dead or is_grabbed() or is_gameplay_input_blocked(): return
	if event.is_action_pressed("toggle_flashlight") and not event.is_echo():
		_toggle_flashlight()
	
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate horizontal (body) normally
		var sensitivity := MOUSE_SENSITIVITY * float(game_settings.get_setting(&"sensitivity"))
		var y_direction := -1.0 if bool(game_settings.get_setting(&"invert_y")) else 1.0
		rotate_y(-event.relative.x * sensitivity)
		# Rotate vertical (camera)
		camera.rotate_x(-event.relative.y * sensitivity * y_direction)
		# Clamp vertical rotation to avoid flipping backward
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	
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
## valid hit height and no active large item are required; jump state must not matter.
func _can_begin_climb(_jump_pressed: bool, w_pressed: bool, is_rv_hit: bool, wall_normal_ok: bool, hit_height_ok: bool) -> bool:
	return not is_crawling() and can_use_hands(2) and not inventory.is_holding_large_item() and w_pressed and is_rv_hit and wall_normal_ok and hit_height_ok

func _show_large_item_climb_feedback() -> void:
	if _large_item_climb_feedback_shown:
		return
	var interaction := get_node_or_null("Camera3D/InteractRay")
	if interaction != null and interaction.has_method("show_feedback"):
		interaction.show_feedback(LARGE_ITEM_CLIMB_MESSAGE)
		_large_item_climb_feedback_shown = true

func _abort_climb_if_holding_large_item() -> bool:
	if not inventory.is_holding_large_item():
		_large_item_climb_feedback_shown = false
		return false
	if locomotion_state != LocomotionState.CLIMBING:
		return false
	_show_large_item_climb_feedback()
	# Preserve the carrier velocity and collision cleanup of every other detach.
	_abort_climb("carrying large item")
	return true

func _is_rv_wall_normal(hit_normal: Vector3, rv_up: Vector3 = Vector3.UP) -> bool:
	return ClimbMath.is_rv_wall_normal(hit_normal, rv_up, CLIMB_WALL_MIN_DOT, CLIMB_WALL_MAX_DOT)

func _is_valid_climb_hit_height(local_hit_y: float) -> bool:
	return ClimbMath.is_valid_hit_height(local_hit_y, CLIMB_MIN_HIT_Y, CLIMB_MAX_HIT_Y)

func _should_disable_body_collision_for_locomotion(_state: int) -> bool:
	return seated_in != null or is_player_dead

func _sync_body_collision_to_locomotion() -> void:
	if body_collision_shape == null:
		return
	if is_player_dead:
		body_collision_shape.set_deferred("disabled", true)
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

func _can_sprint(moving: bool) -> bool:
	return moving and not is_gameplay_input_blocked() and not is_crawling() and not is_grabbed() and get_player_mode() == PlayerMode.NORMAL \
		and not stamina_exhausted and current_stamina > 0.0 and Input.is_action_pressed("sprint")

func _spend_stamina(amount: float) -> bool:
	if current_stamina < amount:
		return false
	current_stamina = maxf(0.0, current_stamina - amount)
	stamina_recovery_delay_remaining = STAMINA_RECOVERY_DELAY
	if current_stamina <= 0.0:
		stamina_exhausted = true
	_update_stamina_bar()
	return true

func _update_stamina(delta: float, sprinting: bool) -> void:
	if sprinting:
		_spend_stamina(minf(current_stamina, SPRINT_STAMINA_PER_SECOND * delta))
		return
	if stamina_recovery_delay_remaining > 0.0:
		stamina_recovery_delay_remaining = maxf(0.0, stamina_recovery_delay_remaining - delta)
		return
	if current_stamina < MAX_STAMINA:
		current_stamina = minf(MAX_STAMINA, current_stamina + STAMINA_RECOVERY_PER_SECOND * delta)
		if stamina_exhausted and current_stamina >= STAMINA_EXHAUSTION_RECOVERY:
			stamina_exhausted = false
		_update_stamina_bar()

func _update_stamina_bar() -> void:
	if health_bar and health_bar.has_method("set_stamina"):
		health_bar.set_stamina(current_stamina, MAX_STAMINA)

func _process_normal_movement(delta: float) -> void:
	var input_allowed := not is_gameplay_input_blocked() and not is_grabbed()
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

	if input_allowed and not is_crawling() and not grab_control.jump_release_required and Input.is_action_just_pressed("jump") and is_on_floor() and _spend_stamina(JUMP_STAMINA_COST):
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2.ZERO
	if input_allowed and Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if input_allowed and Input.is_action_pressed("move_right"):
		input_dir.x += 1
	if input_allowed and Input.is_action_pressed("move_forward"):
		input_dir.y -= 1
	if input_allowed and Input.is_action_pressed("move_back"):
		input_dir.y += 1

	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()

	var sprinting := _can_sprint(input_dir != Vector2.ZERO)
	_update_stamina(delta, sprinting)
	var movement_speed := SPRINT_SPEED if sprinting else SPEED
	if is_crawling(): movement_speed = crawl_speed()
	if crawl_transition_remaining > 0.0: movement_speed = 0.0
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * movement_speed
		velocity.z = direction.z * movement_speed
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
	# A held W gesture gets one reason, not a refreshed toast every physics tick.
	if not Input.is_action_pressed("move_forward") or not inventory.is_holding_large_item():
		_large_item_climb_feedback_shown = false
	if is_gameplay_input_blocked(): return
	if locomotion_state != LocomotionState.NORMAL or is_crawling() or not can_use_hands(2):
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
	if wall_normal_ok and hit_height_ok and inventory.is_holding_large_item():
		_show_large_item_climb_feedback()
		return
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
	if _abort_climb_if_holding_large_item():
		return
	var input_allowed := not is_gameplay_input_blocked() and not is_grabbed()
	if active_climb_rv == null or not is_instance_valid(active_climb_rv):
		_abort_climb("rv invalid")
		return

	# Manual detach: pressing back or jump while climbing exits immediately to avoid floor-intersection stick cases.
	if input_allowed and (Input.is_action_pressed("move_back") or Input.is_action_just_pressed("jump")):
		_abort_climb("manual detach")
		return

	if active_climb_rv is RigidBody3D:
		if (active_climb_rv as RigidBody3D).angular_velocity.length() > CLIMB_MAX_RV_ANGULAR_SPEED:
			_abort_climb("rv angular speed too high")
			return

	var rv_up := active_climb_rv.global_transform.basis.y.normalized()
	if input_allowed and Input.is_action_pressed("move_forward") and ClimbMath.try_roof_transfer(self, body_collision_shape, active_climb_rv, active_wall_normal):
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
	if input_allowed and Input.is_action_pressed("move_forward"):
		vertical_input += 1.0
	if input_allowed and Input.is_action_pressed("move_back"):
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
	if input_allowed and Input.is_action_pressed("move_right"):
		horizontal_input += 1.0
	if input_allowed and Input.is_action_pressed("move_left"):
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
	# Cover restored/direct inventory changes before applying any carrier motion.
	_abort_climb_if_holding_large_item()
	if not Input.is_action_pressed("move_forward"):
		_large_item_climb_feedback_shown = false
	_advance_flashlight(delta)
	if is_player_dead:
		return
	crawl_transition_remaining = maxf(0.0, crawl_transition_remaining - delta)
	if is_instance_valid(seated_in) or in_ui_mode or locomotion_state == LocomotionState.CLIMBING:
		_update_stamina(delta, false)
	# UI/seat lock movement, not the lifetime of damage invulnerability.
	if damage_cooldown > 0.0:
		damage_cooldown = maxf(0.0, damage_cooldown - delta)
	_sync_body_collision_to_locomotion()
	if is_instance_valid(seated_in):
		global_transform = seated_in.global_transform.orthonormalized()
		return
	if in_ui_mode:
		return

	if climb_reenter_cooldown_remaining > 0.0:
		climb_reenter_cooldown_remaining = maxf(0.0, climb_reenter_cooldown_remaining - delta)

	match locomotion_state:
		LocomotionState.NORMAL:
			_process_normal_movement(delta)
			if not is_grabbed(): _try_start_climb()
		LocomotionState.CLIMBING:
			_apply_rv_delta_compensation()
			if locomotion_state == LocomotionState.CLIMBING:
				_process_climbing(delta)

	placement.update_ghost(self)



func take_damage(amount: float):
	if is_player_dead: return
	if damage_cooldown > 0.0: return
	
	current_player_health = maxf(0.0, current_player_health - amount)
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
	if is_player_dead: return
	close_settings()
	var was_seated := is_instance_valid(seated_in)
	var death_view: Vector3 = (seated_in.seat_camera.global_basis if was_seated else camera.global_basis).get_euler()
	grab_control.clear_view_recovery()
	is_player_dead = true
	_advance_flashlight(0.0)
	if is_grabbed(): grab_control.end("death")
	cancel_equipment_placement()
	if is_instance_valid(seated_in): seated_in.exit_seat(true)
	death_velocity = velocity
	if locomotion_state == LocomotionState.CLIMBING:
		death_velocity = climb_carrier_velocity
	elif is_instance_valid(rv_support.rv):
		death_velocity += rv_support.carrier_velocity
	elif not was_seated:
		# Airborne locomotion stores released horizontal platform motion outside
		# velocity. Seat exit already supplies the full world velocity itself.
		death_velocity += Vector3(released_carrier_velocity.x, 0, released_carrier_velocity.z)
	_exit_climb_to_normal()
	rv_support.clear()
	released_carrier_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	# Seat/grab cleanup relinquishes its camera. Keep that final world view
	# while restoring ordinary controller yaw and local pitch ownership.
	global_rotation.y = death_view.y
	camera.rotation = Vector3(clampf(death_view.x, deg_to_rad(-80), deg_to_rad(80)), 0, 0)
	exit_ui_mode()
	if is_instance_valid(held_item_node): held_item_node.hide()
	print(">>> PLAYER DIED! <<<")
	# A hit may arrive while physics queries are being flushed.
	_begin_death_physics.call_deferred()

func _begin_death_physics() -> void:
	if not is_player_dead: return
	_sync_body_collision_to_locomotion()
	visible = true
	camera.make_current()
	ragdoll_control.start(death_velocity)

func _respawn():
	if not is_player_dead: return
	if ragdoll_control.active:
		var standing: Vector3 = ragdoll_control.recovery_position()
		if not standing.is_finite(): return
		load("res://props/corpse.gd").leave_player(self)
		ragdoll_control.stop()
		global_position = standing
	elif not _standing_volume_clear(global_position):
		return
	# Recovery checked the original upright volume before restoring any limb.
	body_state.reset()
	crawl_transition_remaining = 0.0
	is_player_dead = false
	_apply_body_capabilities()
	velocity = Vector3.ZERO
	released_carrier_velocity = Vector3.ZERO
	rv_support.clear()
	_sync_body_collision_to_locomotion()
	set_process_unhandled_input(true)
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_equip_active_slot()
	reset_physics_interpolation()
	current_player_health = max_player_health
	current_stamina = MAX_STAMINA
	stamina_exhausted = false
	stamina_recovery_delay_remaining = 0.0
	_update_health_bar()
	_update_stamina_bar()
	print("Player respawned!")

func refresh_inventory() -> void:
	_abort_climb_if_holding_large_item()
	_update_inventory_display()
	_equip_active_slot()

func is_grabbed() -> bool:
	return is_instance_valid(grab_control) and grab_control.active()

func can_be_grabbed() -> bool:
	return not is_crawling() and is_instance_valid(grab_control) and grab_control.can_begin()

func begin_grab(captor: Node3D, required: int) -> bool:
	if not can_be_grabbed(): return false
	return grab_control.begin(captor, required)

func end_grab(captor: Node3D, reason: String) -> void:
	if grab_control.captor == captor: grab_control.end(reason)

func submit_struggle() -> bool:
	return grab_control.submit_struggle()

func grab_contact_position(side: int, captor: Node3D) -> Vector3:
	var origin := grab_contact_origin()
	if is_grabbed() and is_instance_valid(grab_control.camera): origin = grab_control.camera.global_position
	return captor.grab.head_grip(origin, captor.global_basis, side)

func grab_contact_origin() -> Vector3:
	var view: Camera3D = seated_in.seat_camera if is_instance_valid(seated_in) else camera
	# Stable body/seat anchor for approach checks; visual hands follow the head.
	if is_grabbed(): return view.get_parent().to_global(grab_control.camera_rest_position)
	return view.global_position

func apply_grab_bite(captor: Node3D, fatal: bool) -> void:
	if not is_grabbed() or grab_control.captor != captor or is_player_dead: return
	grab_control.bite_impact()
	var head_bite := fatal or not body_state.has_part(&"left_arm")
	if head_bite:
		current_player_health = 0.0
		sever_part(&"head", {"captor": captor})
		_update_health_bar()
		return
	current_player_health = maxf(0, current_player_health - 50.0)
	damage_cooldown = .5
	sever_part(&"left_arm", {"captor": captor})
	_update_health_bar()
	if current_player_health <= 0: _player_die()

func is_crawling() -> bool:
	return not body_state.has_part(&"left_leg") or not body_state.has_part(&"right_leg")

func usable_arms() -> int:
	return int(body_state.has_part(&"left_arm")) + int(body_state.has_part(&"right_arm"))

func can_use_hands(required: int = 1) -> bool:
	return not is_player_dead and body_state.has_part(&"head") and usable_arms() >= required

func can_drive() -> bool:
	return not is_crawling() and can_use_hands()

func crawl_speed() -> float:
	if usable_arms() == 0: return 0.0
	if usable_arms() == 1: return CRAWL_ONE_ARM_SPEED
	return CRAWL_ONE_LEG_SPEED if body_state.has_part(&"left_leg") or body_state.has_part(&"right_leg") else CRAWL_NO_LEGS_SPEED

func sever_part(part: StringName, context: Dictionary = {}) -> bool:
	if is_player_dead or not PlayerBodyState.PARTS.has(part) or not body_state.has_part(part): return false
	var was_crawling := is_crawling()
	var visuals := get_node_or_null("Visuals")
	# Capture the current animated limb before hiding its mesh and bone branch.
	if visuals and visuals.has_method("detach_part"):
		var detached: Node3D = visuals.detach_part(part, context)
		if part == &"head" and is_instance_valid(detached):
			var view: Camera3D = seated_in.seat_camera if is_instance_valid(seated_in) else camera
			ragdoll_control.follow_detached_head(detached, view.global_transform)
	body_state.sever(part)
	if not was_crawling and is_crawling(): crawl_transition_remaining = 0.45
	_apply_body_capabilities()
	if part == &"head":
		current_player_health = 0.0
		_update_health_bar()
		_player_die()
	return true

func _apply_body_capabilities() -> void:
	if is_crawling(): grab_control.clear_view_recovery()
	if locomotion_state == LocomotionState.CLIMBING and (is_crawling() or not can_use_hands(2)):
		_abort_climb("limb lost")
	if is_placing_equipment() and not can_use_hands(2):
		placement.placing_equipment.cancel_placement()
		placement.placing_equipment = null
		placement._clear_marker()
		placement._hide_slots(self)
	if body_state.has_part(&"head") and is_instance_valid(seated_in) and not can_drive(): seated_in.exit_seat(true)
	var interact := camera.get_node_or_null("InteractRay") if is_instance_valid(camera) else null
	if interact and interact.has_method("cancel_body_operations"): interact.cancel_body_operations()
	_apply_body_collision.call_deferred()
	var visuals := get_node_or_null("Visuals")
	if visuals and visuals.has_method("apply_body_state"): visuals.apply_body_state()
	_equip_active_slot()
	_update_inventory_display()
	_advance_flashlight(0.0)
	body_state_changed.emit()

func _apply_body_collision() -> void:
	if not is_instance_valid(body_collision_shape) or standing_collision_shape == null: return
	if is_crawling():
		var capsule := CapsuleShape3D.new()
		capsule.radius = CRAWL_RADIUS
		capsule.height = CRAWL_ONE_LEG_LENGTH if body_state.has_part(&"left_leg") or body_state.has_part(&"right_leg") else CRAWL_NO_LEGS_LENGTH
		body_collision_shape.shape = capsule
		var standing_capsule := standing_collision_shape as CapsuleShape3D
		var sole_y := standing_collision_transform.origin.y - standing_capsule.height * 0.5
		body_collision_shape.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, sole_y + capsule.radius, 0))
	else:
		body_collision_shape.shape = standing_collision_shape
		body_collision_shape.transform = standing_collision_transform
	_sync_body_collision_to_locomotion()

func _standing_volume_clear(at: Vector3) -> bool:
	if not is_inside_tree() or standing_collision_shape == null: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_collision_shape
	query.transform = Transform3D(global_basis, at) * standing_collision_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
