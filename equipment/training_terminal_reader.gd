extends Node
## A reading session over the original inventory record, never an Item actor.
const UI = preload("res://equipment/training_terminal_ui.gd")
const BOOT = preload("res://equipment/training_terminal_boot.gd")
const SCENE := "res://equipment/training_terminal.tscn"
var current_user: Node3D
var record: Dictionary
var ui_instance: CanvasLayer
var manual_unlocked: bool:
	get: return bool(boot_state().get("manual_unlocked", false))
var completion: String:
	get: return str(boot_state().get("completion", "locked"))

static func open(player: Node3D) -> Node:
	var item: Dictionary = player.inventory.active_item()
	if item.get("scene_path", "") != SCENE or not ItemState.valid(SCENE, item.get("state", {})): return null
	var state: Dictionary = item.state.training_terminal
	if state.version != 2 or not item.state.get("enabled", true) or item.state.condition <= 0 or state.internal_charge < 0.2: return null
	if not player.can_use_hands() or not player.enter_ui_mode(): return null
	var reader = new()
	reader.current_user = player
	reader.record = item
	# All changes are written to the inventory dictionary, not the held preview.
	state.internal_charge = maxf(0.0, state.internal_charge - 0.2)
	player.add_child(reader)
	return reader

func _ready() -> void:
	ui_instance = CanvasLayer.new()
	ui_instance.set_script(UI)
	add_child(ui_instance)
	ui_instance.close_requested.connect(_close_ui)
	ui_instance.current_conditions_visible.connect(_conditions_visible)
	current_user.grab_started.connect(_close_ui)
	current_user.body_state_changed.connect(_validate_user)
	current_user.tree_exiting.connect(_close_ui)
	ui_instance.on_open()

func boot_state() -> Dictionary:
	return record.get("state", {}).get("training_terminal", {})

func start_boot() -> void:
	if _user_valid(): boot_state().boot_started = true

func advance_boot(delta: float) -> void:
	if not _user_valid(): return
	if BOOT.advance(boot_state(), delta):
		var controller := tutorial_controller()
		if controller != null and controller.has_method("terminal_initialized"):
			controller.terminal_initialized(record.state.id, current_user)

func tutorial_controller() -> Node:
	var anchor: Node = current_user
	while is_instance_valid(anchor):
		if anchor.has_meta("entity_domain"):
			var controller := anchor.get_node_or_null("StartRun/Tutorial")
			return controller if controller != null and controller.has_method("terminal_page") and controller.has_method("conditions_viewed") else null
		anchor = anchor.get_parent()
	return null

func _conditions_visible(stage: int) -> void:
	if not _user_valid() or ui_instance.current_page != "conditions": return
	var controller := tutorial_controller()
	if controller == null or controller.get("terminal_id") != record.state.id: return
	var page: Dictionary = controller.terminal_page()
	if page.get("available", false) and page.get("stage", 0) == stage:
		controller.conditions_viewed(record.state.id, current_user)
		ui_instance.refresh()

func _user_valid() -> bool:
	if not is_instance_valid(current_user) or not current_user.is_inside_tree() or is_queued_for_deletion(): return false
	if current_user.is_player_dead or current_user.is_grabbed() or not current_user.can_use_hands() or not current_user.in_ui_mode: return false
	if not is_same(current_user.inventory.active_item(), record): return false
	return ItemState.valid(SCENE, record.get("state", {})) and record.state.get("enabled", true) and record.state.condition > 0.0 and boot_state().internal_charge > 0.0

func _validate_user() -> void:
	if not _user_valid(): _close_ui()

func _physics_process(_delta: float) -> void:
	_validate_user()

func _close_ui() -> void:
	if is_instance_valid(ui_instance): ui_instance.visible = false
	if is_instance_valid(current_user):
		if current_user.grab_started.is_connected(_close_ui): current_user.grab_started.disconnect(_close_ui)
		if current_user.body_state_changed.is_connected(_validate_user): current_user.body_state_changed.disconnect(_validate_user)
		if current_user.tree_exiting.is_connected(_close_ui): current_user.tree_exiting.disconnect(_close_ui)
		current_user.exit_ui_mode()
	current_user = null
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(current_user): _close_ui()
