extends SceneTree
## Unlocked terminal reference, Item round trips, and Esc skip confirmation.
const MANUAL = preload("res://equipment/training_manual.gd")
const SCENE := "res://equipment/training_terminal.tscn"
var failures: Array[String] = []

class TutorialFixture extends Node:
	var terminal_id := "manual-test-terminal"
	var active := true
	var preparing := true
	var has_entry := true
	var skips := 0
	var closed_before_skip := false
	var player: Node3D
	func terminal_page() -> Dictionary:
		return {"available": false, "stage": 9, "title": "Departure"}
	func conditions_viewed(_identity: String, _actor: Node3D) -> void: pass
	func can_restart() -> bool: return active and preparing and has_entry
	func can_skip() -> bool: return active and preparing
	func skip_tutorial() -> bool:
		if not can_skip(): return false
		closed_before_skip = not player.settings_open and not player.get_node("SettingsMenu").visible
		skips += 1
		active = false
		return true

func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value: failures.append(note)
func frames(count: int = 3) -> void:
	for frame in count: await process_frame

func run() -> void:
	var topics := ["driving", "battery", "rvctl", "placement", "recycling", "crafting", "structure", "engine", "tire", "refueling", "departure", "controls"]
	var entries := MANUAL.search("")
	check(entries.size() == topics.size(), "Empty search lists the full reference")
	for topic: String in topics:
		var found := false
		for entry: Dictionary in entries:
			if entry.id == topic: found = true
		check(found, "Manual covers " + topic)
	var battery := MANUAL.search("  BATTERY\tSOCKET  ")
	check(not battery.is_empty() and battery[0].id == "battery", "Search matches case-insensitive words across title and body")
	check(MANUAL.search("nonexistent-topic-919").is_empty() and MANUAL.format("nonexistent-topic-919") == "No matching entries.", "No-result search has clear feedback")
	entries[0].body = "Modified external result"
	check(MANUAL.search("")[0].body != entries[0].body, "Search results cannot mutate the reference")
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
	tutorial.player = player
	await frames()
	rv.get_battery_socket().set_physics_process(false)
	rv.current_power = 80.0
	rv.set_engine_running(false)
	var terminal: Item = load(SCENE).instantiate()
	terminal.persistent_id = tutorial.terminal_id
	WorldEntities.get_container(world).add_child(terminal)
	await frames()
	terminal.pickup(player)
	await frames()
	var locked_record: Dictionary = player.inventory.active_item()
	check(not locked_record.is_empty() and not locked_record.is_large and VehicleSnapshot.valid_item(locked_record), "Normal locked small terminal inventory passes checkpoint validation")
	player.drop_item()
	await frames()
	for item in WorldEntities.get_container(world).get_children():
		if item is Item and item.persistent_id == tutorial.terminal_id: terminal = item
	var tablet: Item = load("res://equipment/tablet_screen.tscn").instantiate()
	var false_size := {"name": "Tablet", "is_large": false, "scene_path": "res://equipment/tablet_screen.tscn", "state": tablet.capture_item_state()}
	check(ItemState.valid(false_size.scene_path, false_size.state) and not VehicleSnapshot.valid_item(false_size), "Other equipment still rejects a falsely small inventory record")
	tablet.free()
	terminal.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), rv)
	terminal.interact_hold(player)
	terminal.unlock_manual("completed")
	var unlocked := terminal.capture_item_state()
	var ui: CanvasLayer = terminal.ui_instance
	check(ui.current_page == "manual" and ui.visible and player.in_ui_mode, "Completion opens Manual in the existing terminal session")
	check(not ui.controls.conditions.visible and not ui.controls.steps.visible and not ui._title.text.contains("offline"), "Completed terminal removes inactive training presentation")
	check(unlocked.id == tutorial.terminal_id and ItemState.valid(SCENE, unlocked), "Unlock retains valid identity and Item state")
	ui._search.text = "healthy spare"
	check(ui._manual.text.contains("Tires and wheel slots"), "Visible search refreshes manual results")
	ui.select_page("conditions")
	check(ui.current_page == "manual", "Training shortcut cannot reopen obsolete conditions")
	var construction: RVStructureConstruction = rv.get_node("StructureSlots").construction
	check(not terminal.is_management_active() and not construction.rejection_reason(terminal, "left_1", "repair").is_empty(), "Unlocked manual grants no construction authority")
	terminal._close_ui()
	var before := rv.current_power
	terminal.interact_hold(player)
	check(ui.current_page == "manual" and is_equal_approx(rv.current_power, before - 0.2), "Reopening defaults to Manual with normal power cost")
	rv.current_power = 0.0
	terminal._physics_process(0.0)
	check(not ui.visible and not player.in_ui_mode, "Manual respects power-loss session cleanup")
	rv.current_power = 80.0
	terminal.detach_from_support()
	check(player.add_prop_item(terminal, SCENE), "Unlocked terminal enters normal inventory")
	terminal.queue_free()
	await frames()
	check(player.inventory.active_item().state == unlocked, "Inventory retains terminal identity and completion")
	check(not player.inventory.active_item().is_large and VehicleSnapshot.valid_item(player.inventory.active_item()), "Unlocked small terminal inventory remains valid for checkpoint saving")
	player.drop_item()
	await frames()
	var dropped: Item
	for item in WorldEntities.get_container(world).get_children():
		if item is Item and item.persistent_id == unlocked.id: dropped = item
	check(dropped != null and dropped.capture_item_state() == unlocked, "Drop restores the same manual Item")
	if dropped != null:
		dropped.unlock_manual("skipped")
		dropped.confirm_placement(dropped.global_transform, rv)
		dropped.interact_hold(player)
		check(dropped.ui_instance.current_page == "manual" and dropped.ui_instance._title.text.contains("Skipped"), "Skipped record also opens Manual")
		dropped._close_ui()
		var other_shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
		world.add_child(other_shell)
		var other_rv: Chassis = other_shell.get_node("Chassis")
		other_rv.freeze = true
		other_rv.set_physics_process(false)
		await frames()
		other_rv.get_battery_socket().set_physics_process(false)
		other_rv.current_power = 80.0
		dropped.confirm_placement(dropped.global_transform, other_rv)
		check(dropped.get_connected_rv() == other_rv and dropped.persistent_id == unlocked.id and dropped.manual_unlocked, "Moving to another RV keeps Item identity and manual")
		var viewport := SubViewport.new()
		viewport.size = root.size
		viewport.own_world_3d = true
		world.add_child(viewport)
		var independent := Node3D.new()
		independent.set_meta("entity_domain", true)
		viewport.add_child(independent)
		WorldEntities.transfer(other_shell, independent)
		check(dropped.tutorial_controller() == null and dropped.manual_unlocked, "Independent world retains manual without borrowing tutorial")
		dropped.ui_instance.on_open()
		check(dropped.ui_instance.current_page == "manual" and dropped.ui_instance._manual.text.contains("Driving and parking"), "Reference works outside the tutorial world")
	await check_settings_confirmation(player, tutorial)
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: searchable manual, completed/skipped terminal lifecycle and Esc skip confirmation")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check_settings_confirmation(player: Node3D, tutorial: TutorialFixture) -> void:
	var menu: CanvasLayer = player.get_node("SettingsMenu")
	check(menu.open_menu(), "Esc settings opens before skipping")
	check(menu._skip_tutorial.visible and menu._restart_stage.visible, "Preparing active training exposes Skip and Restart")
	menu._show_skip_tutorial()
	check(menu._modal_kind == "skip_tutorial" and menu._modal_cancel.has_focus(), "Skip requires confirmation and defaults to Cancel")
	menu._cancel_modal()
	await frames()
	check(tutorial.skips == 0 and menu.visible and player.settings_open, "Cancel leaves training and menu intact")
	tutorial.has_entry = false
	menu._update_status()
	check(not menu._restart_stage.visible and menu._skip_tutorial.visible, "Skip stays available without an entry snapshot")
	menu._show_skip_tutorial()
	tutorial.preparing = false
	menu._accept_modal()
	await frames()
	check(tutorial.skips == 0 and menu.visible, "Started journey invalidates pending Skip confirmation")
	menu._update_status()
	check(not menu._skip_tutorial.visible and not menu._restart_stage.visible, "Started journey hides tutorial actions")
	tutorial.preparing = true
	menu._show_skip_tutorial()
	menu._accept_modal()
	check(not menu.visible and not player.settings_open and tutorial.skips == 0, "Confirm safely closes settings before deferred skip")
	await frames()
	check(tutorial.skips == 1 and tutorial.closed_before_skip, "Deferred Skip invokes the controller once after releasing input")
	menu.open_menu()
	check(not menu._skip_tutorial.visible and not menu._restart_stage.visible, "Completed/skipped training cannot re-enter through settings")
	menu.close_menu()
