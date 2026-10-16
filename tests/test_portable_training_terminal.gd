extends SceneTree
## Boot state, original wall removal and inventory reading without Item services.
const SCENE := "res://equipment/training_terminal.tscn"
var failures: Array[String] = []

class Course extends Node:
	var terminal_id := "portable-terminal-test"
	var boots := 0
	var pickups := 0
	var views := 0
	func terminal_page() -> Dictionary:
		return {"stage": 1, "title": "Terminal orientation", "available": true,
			"conditions": [{"label": "Take this terminal with you.", "complete": pickups > 0}],
			"steps": ["Esc Close. Hold F to remove the terminal."], "reference": ["T Read held terminal"]}
	func conditions_viewed(_identity: String, _player: Node3D) -> void: views += 1
	func terminal_initialized(_identity: String, _player: Node3D) -> void: boots += 1
	func terminal_docked_pickup(identity: String, player: Node3D) -> void:
		if identity == terminal_id and player.inventory.active_item().state.id == identity: pickups += 1

func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value: failures.append(note)
func frames(count: int = 3) -> void:
	for frame in count: await process_frame
func enter() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = KEY_ENTER
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var owner := Node.new()
	owner.name = "StartRun"
	world.add_child(owner)
	var course := Course.new()
	course.name = "Tutorial"
	owner.add_child(course)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	var dock := StaticBody3D.new()
	dock.set_meta("training_terminal_dock", course.terminal_id)
	world.add_child(dock)
	var terminal: TrainingTerminal = load(SCENE).instantiate()
	terminal.persistent_id = course.terminal_id
	terminal.configure_portable_terminal()
	WorldEntities.get_container(world).add_child(terminal)
	terminal.confirm_placement(Transform3D.IDENTITY, world, dock)
	await frames()
	check(terminal.get_connected_rv() == null and terminal.can_operate(), "The original static dock works without an RV")
	check(not terminal.can_pickup(player) and not player.add_prop_item(terminal, SCENE) and terminal.is_fixed, "Initialization lock also protects the native inventory transaction")
	terminal.interact_hold(player)
	await frames()
	check(terminal.ui_instance._boot.visible and not terminal.ui_instance._screen.visible and course.views == 0 and course.boots == 0, "Opening shows only TTY; conditions and initialization remain unearned")
	check(terminal.ui_instance._boot._text.get_parsed_text().contains("Press ENTER to boot the system."), "TTY always includes the exact Enter prompt before boot")
	await enter()
	await create_timer(0.25).timeout
	var elapsed: float = terminal.boot_state().boot_elapsed
	await enter()
	check(terminal.boot_state().boot_elapsed >= elapsed and terminal.boot_state().boot_started, "Repeated Enter preserves the running boot")
	terminal._close_ui()
	var saved := terminal.capture_item_state()
	check(ItemState.valid(SCENE, saved) and not saved.training_terminal.initialized, "An interrupted boot has valid persistent partial state")
	await create_timer(0.1).timeout
	check(terminal.capture_item_state() == saved and course.boots == 0, "Closed boot pauses without completing initialization")
	terminal.restore_item_state(saved)
	check(course.boots == 0 and not terminal.has_completed_boot(), "Restoring partial progress never grants initialization")
	terminal.interact_hold(player)
	check(terminal.ui_instance._boot.visible and terminal.boot_state().boot_elapsed == saved.training_terminal.boot_elapsed, "Reopening resumes the existing boot instead of restarting")
	await create_timer(6.0).timeout
	await frames()
	check(terminal.has_completed_boot() and course.boots == 1 and not terminal.boot_state().dock_locked, "Six-second boot completes once and unlocks the original dock")
	check(not terminal.ui_instance._boot.visible and terminal.ui_instance._screen.visible and terminal.ui_instance.current_page == "conditions" and terminal.ui_instance._conditions.text.contains("Take this terminal with you."), "Completed boot hands off to the existing Conditions TUI")
	terminal._close_ui()
	terminal.interact_hold(player)
	check(not terminal.ui_instance._boot.visible and course.boots == 1, "Subsequent opens go straight to the existing TUI")
	terminal._close_ui()
	# Full inventory fails before native detach, so it cannot award removal.
	for index in PlayerInventory.MAX_SLOTS: player.inventory.items.append({})
	terminal.pickup(player)
	check(terminal.is_fixed and course.pickups == 0, "Failed inventory transfer retains original dock and earns no removal")
	player.inventory.items.clear()
	terminal.pickup(player)
	check(course.pickups == 1 and player.inventory.active_item().state.id == course.terminal_id, "Successful removal awards the same original ID only after inventory owns it")
	await frames()
	var original: Dictionary = player.inventory.active_item()
	var preview: Item = player.held_item_node
	var before: float = original.state.training_terminal.internal_charge
	preview.interact_hold(player)
	check(not player.in_ui_mode and original.state.training_terminal.internal_charge == before, "The presentation-only Item cannot open a service or spend canonical power")
	var reader: Node = player.read_held_terminal()
	await frames()
	check(reader != null and reader._user_valid() and is_same(reader.record, original), "Held reading is backed by the original active inventory dictionary")
	check(not preview.can_operate() and preview.ui_instance == null and not reader is Item and player.inventory.items.size() == 1, "Reader creates no Item owner and keeps held preview services disabled")
	check(original.state.training_terminal.internal_charge < before and reader.ui_instance._screen.visible and not reader.ui_instance._boot.visible, "Held read uses internal power and opens existing TUI directly")
	reader._close_ui()
	await frames()
	check(not player.in_ui_mode and player.held_item_node == preview, "Closing held read preserves the existing preview and inventory item")
	reader = player.read_held_terminal()
	await frames()
	player.inventory.items[0] = original.duplicate(true)
	reader._physics_process(0.0)
	check(not player.in_ui_mode, "Replacing the original inventory record invalidates and closes its reading session")
	await frames()
	var active: Dictionary = player.inventory.active_item()
	var retained_charge: float = active.state.training_terminal.internal_charge
	active.state.training_terminal.internal_charge = 0.0
	check(player.read_held_terminal() == null and not player.in_ui_mode and active.state.training_terminal.internal_charge == 0.0, "An exhausted internal supply refuses held reading without changing ownership")
	active.state.training_terminal.internal_charge = retained_charge
	# Damage/support loss cannot masquerade as successful original-dock removal.
	player.drop_item()
	await frames()
	var dropped: TrainingTerminal
	for item in WorldEntities.get_container(world).get_children():
		if item is TrainingTerminal: dropped = item
	if dropped != null:
		dropped.pickup(player)
		check(course.pickups == 1, "Loose pickup after a drop cannot award another original-dock transaction")
	var invalid := saved.duplicate(true)
	invalid.training_terminal.initialized = true
	check(not ItemState.valid(SCENE, invalid), "A completion flag without the completed boot state is rejected")
	invalid = saved.duplicate(true)
	invalid.training_terminal.boot_elapsed = NAN
	check(not ItemState.valid(SCENE, invalid), "Non-finite boot progress is rejected")
	world.queue_free()
	await frames()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: portable training terminal boot, dock transactions and original-record reader")
	quit(0 if failures.is_empty() else 1)
