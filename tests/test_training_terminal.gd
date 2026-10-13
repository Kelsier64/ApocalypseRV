extends SceneTree
## Real Item/UI/player ownership with a scoped tutorial presentation fixture.
const SCENE := "res://equipment/training_terminal.tscn"
var failures: Array[String] = []

class TutorialFixture extends Node:
	var terminal_id := "terminal-test"
	var views := 0
	var stage := 1
	var available := true
	func terminal_page() -> Dictionary:
		return {"stage": stage, "title": "Basic operation and driving", "available": available,
			"conditions": [{"id": "view", "label": "Read this stage's conditions", "complete": views > 0}],
			"steps": ["Read the conditions, then pick up the flashlight."], "reference": ["E Pick up", "Esc Close terminal"]}
	func conditions_viewed(id: String, player: Node3D) -> void:
		if id == terminal_id and player.in_ui_mode: views += 1

func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value: failures.append(note)
func frames(count: int = 3) -> void:
	for frame in count: await process_frame
func tap(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await frames()

func run() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var run_owner := Node.new()
	run_owner.name = "StartRun"
	world.add_child(run_owner)
	var tutorial := TutorialFixture.new()
	tutorial.name = "Tutorial"
	run_owner.add_child(tutorial)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(20, 2, 0)
	world.add_child(player)
	player.set_physics_process(false)
	await frames()
	rv.get_battery_socket().set_physics_process(false)
	rv.current_power = 80.0
	rv.set_engine_running(false)
	var terminal: Item = load(SCENE).instantiate()
	terminal.persistent_id = tutorial.terminal_id
	WorldEntities.get_container(world).add_child(terminal)
	await frames()
	var initial := terminal.capture_item_state()
	check(ItemState.valid(SCENE, initial), "New terminal has valid versioned locked state")
	check(tutorial.views == 0 and not terminal.ui_instance.visible, "Ready and state capture do not count as viewing conditions")
	var before := rv.current_power
	terminal.interact_hold(player)
	check(not player.in_ui_mode and rv.current_power == before, "Loose terminal cannot open or consume power")
	terminal.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), rv)
	terminal.set_enabled(false)
	terminal.interact_hold(player)
	check(not player.in_ui_mode and rv.current_power == before, "Disabled terminal refuses without power cost")
	terminal.set_enabled(true)
	player.enter_ui_mode()
	terminal.interact_hold(player)
	check(not terminal.ui_instance.visible and rv.current_power == before, "Existing player UI owner refuses the terminal without charging")
	player.exit_ui_mode()
	rv.current_power = 0.1
	terminal.interact_hold(player)
	check(not terminal.ui_instance.visible and not player.in_ui_mode and is_equal_approx(rv.current_power, 0.1), "Insufficient power preserves player and energy")
	rv.current_power = 80.0
	terminal.interact_hold(player)
	check(terminal.ui_instance.visible and player.in_ui_mode and is_equal_approx(rv.current_power, 79.8), "Mounted terminal enters player UI and consumes exactly 0.2 power")
	terminal.interact_hold(player)
	check(is_equal_approx(rv.current_power, 79.8), "Repeated hold while open does not charge again")
	terminal.ui_instance.select_page("steps")
	await frames()
	check(tutorial.views == 0, "Switching away before current conditions are presented does not count")
	terminal.ui_instance.select_page("conditions")
	await frames()
	check(tutorial.views == 1, "Visible current conditions on the designated terminal count once")
	var construction: RVStructureConstruction = rv.get_node("StructureSlots").construction
	check(not construction.rejection_reason(terminal, "left_1", "repair").is_empty() and not terminal.is_management_active(), "Training terminal cannot authorize rvctl structure construction")
	await tap(KEY_F3)
	check(terminal.ui_instance.current_page == "reference", "F3 navigates to English control reference")
	await tap(KEY_ESCAPE)
	check(not terminal.ui_instance.visible and not player.in_ui_mode and not player.settings_open and player.get_player_mode() == player.PlayerMode.NORMAL, "Esc closes terminal and restores player input without opening settings")
	# Headless DisplayServer intentionally ignores native mouse capture.
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Esc restores native mouse capture")
	tutorial.terminal_id = "other-terminal"
	terminal.interact_hold(player)
	await frames()
	check(tutorial.views == 1, "A terminal with the wrong persistent identity cannot count conditions")
	terminal._close_ui()
	tutorial.terminal_id = terminal.persistent_id
	tutorial.stage = 2
	tutorial.available = false
	terminal.interact_hold(player)
	await frames()
	check(tutorial.views == 1, "Unimplemented stage placeholder does not count conditions")
	terminal._close_ui()
	tutorial.stage = 1
	tutorial.available = true
	terminal.interact_hold(player)
	rv.current_power = 0.0
	terminal._physics_process(0.0)
	check(not terminal.ui_instance.visible and not player.in_ui_mode, "Power loss closes the terminal")
	rv.current_power = 80.0
	terminal.interact_hold(player)
	player.grab_started.emit()
	check(not terminal.ui_instance.visible and not player.in_ui_mode, "Grab start closes the terminal")
	terminal.interact_hold(player)
	player.body_state.sever(&"left_arm")
	player.body_state.sever(&"right_arm")
	player.body_state_changed.emit()
	check(not terminal.ui_instance.visible and not player.in_ui_mode, "Loss of usable hands closes the terminal")
	player.body_state.reset()
	terminal.interact_hold(player)
	player.is_player_dead = true
	terminal._physics_process(0.0)
	check(not terminal.ui_instance.visible and not player.in_ui_mode, "Death closes the terminal")
	player.is_player_dead = false
	terminal.unlock_manual("skipped")
	var unlocked := terminal.capture_item_state()
	check(ItemState.valid(SCENE, unlocked) and unlocked.training_terminal.completion == "skipped", "Skipped completion is a valid searchable-manual state")
	check_invalid_states(initial)
	var preview: Item = load(SCENE).instantiate()
	preview.presentation_only = true
	preview.restore_item_state(unlocked)
	world.add_child(preview)
	check(preview.capture_item_state() == unlocked and preview.ui_instance == null and not preview.can_operate(), "Held preview preserves ID/manual state without UI or services")
	preview.free()
	var support := StaticBody3D.new()
	rv.add_child(support)
	terminal.confirm_placement(terminal.global_transform, rv, support)
	terminal.interact_hold(player)
	support.queue_free()
	await frames()
	check(not terminal.is_fixed and not terminal.ui_instance.visible and not player.in_ui_mode, "Destroyed mount support closes UI and releases the loose Item")
	check(player.add_prop_item(terminal, SCENE), "Normal inventory transaction accepts the terminal")
	terminal.queue_free()
	await frames()
	check(player.inventory.active_item().state == unlocked and player.held_item_node.presentation_only, "Inventory and held presentation retain exact terminal identity and manual unlock")
	player.drop_item()
	await frames()
	var dropped: Item
	for item in WorldEntities.get_container(world).get_children():
		if item is Item and item.persistent_id == unlocked.id: dropped = item
	check(dropped != null and dropped.capture_item_state() == unlocked and not dropped.is_fixed, "Drop restores the same unlocked terminal as one world Item")
	if dropped != null:
		dropped.confirm_placement(dropped.global_transform, rv)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 720)
		viewport.own_world_3d = true
		world.add_child(viewport)
		var independent := Node3D.new()
		independent.set_meta("entity_domain", true)
		viewport.add_child(independent)
		WorldEntities.transfer(shell, independent)
		check(dropped.capture_item_state() == unlocked and dropped.tutorial_controller() == null and not WorldEntities.same_world(dropped, player), "World transfer preserves terminal state and does not borrow an outer tutorial controller")
		dropped.interact_hold(player)
		check(not dropped.ui_instance.visible and not player.in_ui_mode, "A player in another World3D cannot open the terminal")
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: training terminal lifecycle, power, UI presentation and versioned Item state")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check_invalid_states(state: Dictionary) -> void:
	for value in [null, {}, {"version": 2, "manual_unlocked": false, "completion": "locked"},
		{"version": 1.0, "manual_unlocked": false, "completion": "locked"},
		{"version": 1, "manual_unlocked": "false", "completion": "locked"},
		{"version": 1, "manual_unlocked": false, "completion": "completed"},
		{"version": 1, "manual_unlocked": true, "completion": "locked"},
		{"version": 1, "manual_unlocked": false, "completion": "other"},
		{"version": 1, "manual_unlocked": false, "completion": "locked", "extra": true}]:
		var invalid := state.duplicate(true)
		invalid.training_terminal = value
		check(not ItemState.valid(SCENE, invalid), "Malformed terminal subtype state is rejected: " + str(value))
	var missing := state.duplicate(true)
	missing.erase("training_terminal")
	check(not ItemState.valid(SCENE, missing), "Registered terminal requires its subtype state")
	check(not ItemState.valid("res://equipment/tablet_screen.tscn", state), "Training state is forbidden on the vehicle tablet")
