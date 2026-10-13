extends Item
class_name TrainingTerminal
## A normal mounted Item. Tutorial progress belongs to this world's StartRun.
const UI = preload("res://equipment/training_terminal_ui.gd")
const STATE_VERSION := 1
@export var power_cost_per_open: float = 0.2
var ui_instance: CanvasLayer
var current_user: Node3D
var manual_unlocked := false
var completion := "locked"

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
	state["training_terminal"] = {"version": STATE_VERSION, "manual_unlocked": manual_unlocked, "completion": completion}
	return state

func restore_item_state(state: Dictionary) -> void:
	var saved: Variant = state.get("training_terminal")
	if not ItemState.valid_training_terminal(saved): return
	_close_ui()
	super.restore_item_state(state)
	manual_unlocked = saved.manual_unlocked
	completion = saved.completion

func unlock_manual(result: String) -> void:
	if result not in ["completed", "skipped"]: return
	manual_unlocked = true
	completion = result
	if is_instance_valid(ui_instance): ui_instance.refresh()

func get_interaction_prompt(player: Node3D) -> String:
	if is_instance_valid(processing_owner): return item_name + " | Recycling"
	if not player.can_use_hands(): return item_name + " | A usable arm is required"
	if not is_fixed: return item_name + " | E Pick up"
	return item_name + " | Hold E Open terminal | Hold F Remove"

func interact(player: Node3D) -> String:
	return pickup(player) if not is_fixed else "Hold E to open. Hold F to remove."

func pickup(player: Node3D) -> String:
	if not can_pickup(player): return "Cannot pick up: item unavailable or inventory full."
	if scene_file_path.is_empty(): return "Cannot pick up: item has no saved scene."
	if not player.add_prop_item(self, scene_file_path): return "Cannot pick up: free an inventory slot first."
	queue_free()
	return "Picked up " + item_name

func can_operate() -> bool:
	return not is_queued_for_deletion() and not is_instance_valid(processing_owner) and super.can_operate()

func interact_hold(player: Node3D) -> void:
	if not is_instance_valid(player) or not player.can_use_hands() or not WorldEntities.same_world(self, player): return
	if not can_operate() or not is_instance_valid(ui_instance) or ui_instance.visible: return
	if not get_connected_rv().has_usable_power(power_cost_per_open): return
	if not player.enter_ui_mode(): return
	if not consume_rv_power(power_cost_per_open):
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
	return get_connected_rv().has_usable_power()

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
