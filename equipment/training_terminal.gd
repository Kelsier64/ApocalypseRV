extends Item
class_name TrainingTerminal
## A normal mounted Item. Tutorial progress belongs to this world's StartRun.
const UI = preload("res://equipment/training_terminal_ui.gd")
const STATE_VERSION := 1
const BOOT = preload("res://equipment/training_terminal_boot.gd")
@export var power_cost_per_open: float = 0.2
var ui_instance: CanvasLayer
var current_user: Node3D
var manual_unlocked := false
var completion := "locked"
var _portable: Dictionary = {}

func configure_portable_terminal() -> void:
	# Only the new course opts in; old terminals preserve their exact v1 data.
	if _portable.is_empty(): _portable = BOOT.fresh_state()

func boot_state() -> Dictionary:
	if _portable.is_empty(): return {}
	_portable.manual_unlocked = manual_unlocked
	_portable.completion = completion
	return _portable

func has_completed_boot() -> bool:
	return not _portable.is_empty() and _portable.initialized and _portable.boot_started and _portable.boot_elapsed == BOOT.DURATION

func start_boot() -> void:
	if _user_valid() and ui_instance.visible and not _portable.is_empty() and not _portable.initialized:
		_portable.boot_started = true

func advance_boot(delta: float) -> void:
	if not _user_valid() or not ui_instance.visible or _portable.is_empty(): return
	if BOOT.advance(_portable, delta):
		var controller := tutorial_controller()
		if controller != null and controller.has_method("terminal_initialized"):
			controller.terminal_initialized(persistent_id, current_user)

func _ready() -> void:
	super._ready()
	if presentation_only: return
	ui_instance = CanvasLayer.new()
	ui_instance.set_script(UI)
	ui_instance.visible = false
	add_child(ui_instance)
	ui_instance.close_requested.connect(_close_ui)
	ui_instance.current_conditions_visible.connect(_conditions_visible)
	availability_changed.connect(_validate_user)
	removing.connect(_close_ui)

func capture_item_state() -> Dictionary:
	var state := super.capture_item_state()
	state["training_terminal"] = boot_state().duplicate(true) if not _portable.is_empty() else {"version": STATE_VERSION, "manual_unlocked": manual_unlocked, "completion": completion}
	return state

func restore_item_state(state: Dictionary) -> void:
	var saved: Variant = state.get("training_terminal")
	if not ItemState.valid_training_terminal(saved): return
	_close_ui()
	super.restore_item_state(state)
	manual_unlocked = saved.manual_unlocked
	completion = saved.completion
	_portable = saved.duplicate(true) if saved.version == 2 else {}

func unlock_manual(result: String) -> void:
	if result not in ["completed", "skipped"]: return
	manual_unlocked = true
	completion = result
	if is_instance_valid(ui_instance): ui_instance.select_page("manual")

func get_interaction_prompt(player: Node3D) -> String:
	if is_instance_valid(processing_owner): return item_name + " | Recycling"
	if not player.can_use_hands(): return item_name + " | A usable arm is required"
	if not is_fixed: return item_name + " | E Pick up"
	if not _portable.is_empty() and _portable.dock_locked: return item_name + " | Hold E Open terminal | Dock locked"
	return item_name + " | Hold E Open terminal | Hold F Remove"

func interact(player: Node3D) -> String:
	if not _portable.is_empty() and _portable.dock_locked: return "Hold E to open the terminal. Initialize it to release the dock."
	return pickup(player) if not is_fixed else "Hold E to open. Hold F to remove."

func pickup(player: Node3D) -> String:
	if not _portable.is_empty() and _portable.dock_locked: return "Initialize the terminal before removing it from its dock."
	if not can_pickup(player): return "Cannot pick up: item unavailable or inventory full."
	if scene_file_path.is_empty(): return "Cannot pick up: item has no saved scene."
	var from_original_dock: bool = is_fixed and is_instance_valid(mount_support) and mount_support.get_meta("training_terminal_dock", "") == persistent_id
	var controller := tutorial_controller()
	if not player.add_prop_item(self, scene_file_path): return "Cannot pick up: free an inventory slot first."
	if from_original_dock and has_completed_boot() and controller != null and controller.has_method("terminal_docked_pickup"):
		controller.terminal_docked_pickup(persistent_id, player)
	queue_free()
	return "Picked up " + item_name

func can_pickup(player: Node3D) -> bool:
	return (_portable.is_empty() or not _portable.dock_locked) and super.can_pickup(player)

func can_operate() -> bool:
	if is_queued_for_deletion() or is_instance_valid(processing_owner): return false
	if _portable.is_empty(): return super.can_operate()
	return not presentation_only and is_fixed and enabled and not support_lost and not is_being_placed and not is_destroyed and current_health > 0.0

func _has_power(amount: float = 0.01) -> bool:
	var rv := get_connected_rv()
	return (rv != null and rv.has_usable_power(amount)) or (not _portable.is_empty() and _portable.internal_charge > 0.0 and _portable.internal_charge >= amount)

func _consume_open_power() -> bool:
	var rv := get_connected_rv()
	if rv != null and rv.has_usable_power(power_cost_per_open): return rv.consume_power(power_cost_per_open)
	if _portable.is_empty() or not _has_power(power_cost_per_open): return false
	_portable.internal_charge = maxf(0.0, _portable.internal_charge - power_cost_per_open)
	return true

func interact_hold(player: Node3D) -> void:
	if not is_instance_valid(player) or not player.can_use_hands() or not WorldEntities.same_world(self, player): return
	if not can_operate() or not is_instance_valid(ui_instance) or ui_instance.visible: return
	if not _has_power(power_cost_per_open): return
	if not player.enter_ui_mode(): return
	if not _consume_open_power():
		player.exit_ui_mode()
		return
	current_user = player
	player.grab_started.connect(_close_ui)
	player.body_state_changed.connect(_on_body_state_changed)
	player.tree_exiting.connect(_close_ui)
	ui_instance.visible = true
	ui_instance.on_open()

func tutorial_controller() -> Node:
	# Stop at this entity domain, including independent POI worlds. Never find
	# a tutorial through the active scene or another arbitrary world node.
	var anchor: Node = self
	while is_instance_valid(anchor):
		if anchor.has_meta("entity_domain"):
			var controller := anchor.get_node_or_null("StartRun/Tutorial")
			if controller != null and controller.has_method("terminal_page") and controller.has_method("conditions_viewed"):
				return controller
			return null
		anchor = anchor.get_parent()
	return null

func is_management_active() -> bool:
	# Vehicle structure construction remains exclusively authorized by rvctl.
	return false

func _conditions_visible(stage: int) -> void:
	if not _user_valid() or not ui_instance.visible or ui_instance.current_page != "conditions": return
	var controller := tutorial_controller()
	if controller == null or controller.get("terminal_id") != persistent_id: return
	var page: Dictionary = controller.terminal_page()
	if not page.get("available", false) or page.get("stage", 0) != stage: return
	controller.conditions_viewed(persistent_id, current_user)
	ui_instance.refresh()

func _user_valid() -> bool:
	if not is_instance_valid(current_user) or not current_user.is_inside_tree(): return false
	if not can_operate() or not WorldEntities.same_world(self, current_user): return false
	if current_user.is_player_dead or current_user.is_grabbed() or not current_user.can_use_hands() or not current_user.in_ui_mode: return false
	return _has_power()

func _validate_user() -> void:
	if is_instance_valid(current_user) and not _user_valid(): _close_ui()

func _on_body_state_changed() -> void:
	_validate_user()

func _physics_process(_delta: float) -> void:
	_validate_user()

func _on_service_stopped() -> void:
	_close_ui()

func _close_ui() -> void:
	if is_instance_valid(ui_instance): ui_instance.visible = false
	if is_instance_valid(current_user):
		if current_user.grab_started.is_connected(_close_ui): current_user.grab_started.disconnect(_close_ui)
		if current_user.body_state_changed.is_connected(_on_body_state_changed): current_user.body_state_changed.disconnect(_on_body_state_changed)
		if current_user.tree_exiting.is_connected(_close_ui): current_user.tree_exiting.disconnect(_close_ui)
		current_user.exit_ui_mode()
	current_user = null

func begin_world_transfer() -> void:
	_close_ui()
	super.begin_world_transfer()

func _exit_tree() -> void:
	_close_ui()
	super._exit_tree()
