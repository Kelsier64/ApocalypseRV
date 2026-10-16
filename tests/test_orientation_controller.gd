extends SceneTree
## Native boot, mounted Item pickup and inventory ownership in the RV-free room.
const COURSE = preload("res://world/tutorial_shelter/orientation_controller.gd")
const SCENE := "res://equipment/training_terminal.tscn"
var failures: Array[String] = []

class WorldFixture extends Node3D:
	signal ready_for_play
	var fresh_start := true
	var play_ready := true

class RunFixture extends Node:
	var phase := "preparing"
	var shelter: Node3D

class CheckpointInput extends "res://rv/checkpoint.gd":
	var save_requests := 0
	func save_world(_world: Node, _path: String) -> bool:
		save_requests += 1
		return true # Input routing probe never writes the user's manual file.

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func frames(count := 3) -> void:
	for index in count: await process_frame

func new_terminal(world: Node3D, support: Node3D, id: String) -> TrainingTerminal:
	var terminal: TrainingTerminal = load(SCENE).instantiate()
	terminal.persistent_id = id
	terminal.configure_portable_terminal()
	WorldEntities.get_container(world).add_child(terminal)
	support.set_meta("training_terminal_dock", id)
	terminal.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -30)), support, support)
	terminal.set_physics_process(false)
	return terminal

func run() -> void:
	var world := WorldFixture.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var checkpoint_input := CheckpointInput.new()
	root.add_child(checkpoint_input)
	var save_key := InputEventKey.new()
	save_key.pressed = true
	save_key.physical_keycode = KEY_F6
	world.scene_file_path = "res://tests/rv_climb_playground.tscn"
	checkpoint_input._unhandled_input(save_key)
	check(checkpoint_input.save_requests == 0, "Unrelated playgrounds cannot route checkpoint hotkeys")
	world.scene_file_path = "res://tests/orientation_playground.tscn"
	checkpoint_input._unhandled_input(save_key)
	check(checkpoint_input.save_requests == 1, "The inherited orientation F6 scene routes its save hotkey to the production checkpoint")
	checkpoint_input.free()
	var owner := RunFixture.new()
	owner.name = "StartRun"
	world.add_child(owner)
	owner.shelter = Node3D.new()
	owner.shelter.name = "Shelter"
	world.add_child(owner.shelter)
	var collision := Node3D.new()
	collision.name = "Collision"
	owner.shelter.add_child(collision)
	var support := StaticBody3D.new()
	support.name = "TerminalSupport"
	collision.add_child(support)
	var tutorial := COURSE.new()
	tutorial.name = "Tutorial"
	owner.add_child(tutorial)
	tutorial.set_physics_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector3(0, 1, -30)
	world.add_child(player)
	player.set_physics_process(false)
	var terminal := new_terminal(world, support, "orientation-terminal")
	await frames()
	world.ready_for_play.emit()
	check(tutorial.initialized() and tutorial.terminal_id == terminal.persistent_id and tutorial.designated_rv() == null, "Original wall dock initializes the course without any RV")
	check(not tutorial.inner_gate_unlocked() and not tutorial.terminal_page().available, "Fresh room hides conditions and keeps inner gate locked")
	terminal.pickup(player)
	check(player.inventory.items.is_empty() and terminal.is_fixed, "Native terminal pickup refuses before boot initialization")
	terminal.interact_hold(player)
	tutorial.conditions_viewed(terminal.persistent_id, player)
	tutorial.terminal_initialized(terminal.persistent_id, player)
	check(not tutorial.flags.boot_complete, "Opening, reading and premature completion callbacks cannot initialize")
	terminal.start_boot()
	terminal.advance_boot(2.0)
	terminal._close_ui()
	terminal.advance_boot(10.0)
	check(not tutorial.flags.boot_complete and terminal.boot_state().boot_elapsed == 2.0, "Closed UI pauses partial boot without progress evidence")
	terminal.interact_hold(player)
	terminal.advance_boot(4.0)
	check(tutorial.flags.boot_complete and not tutorial.inner_gate_unlocked(), "Successful complete boot records initialization but does not open the gate")
	check(tutorial.terminal_page().conditions[0].label == "Take this terminal with you.", "Boot hands off to the native Conditions page with the exact removal instruction")
	terminal._close_ui()
	var booted := tutorial.capture()
	var restored := COURSE.new()
	check(restored.apply_state(booted) and restored.capture(false) == booted, "Boot evidence round-trips with an independent versioned course child")
	var invalid := booted.duplicate(true)
	invalid.flags.workshop_entered = true
	check(not restored.apply_state(invalid) and restored.capture() == booted, "Rejected inconsistent restore leaves current state unchanged")
	for bad in [{}, {"version": 3}, []]: check(not COURSE.validate_state(bad), "Legacy or malformed course state is rejected")
	var bad_status := booted.duplicate(true)
	bad_status.status = "completed"
	check(not COURSE.validate_state(bad_status), "Stage one cannot fabricate full-course completion")
	restored.free()
	for index in PlayerInventory.MAX_SLOTS: player.inventory.add_item("Filler", false, "", {})
	terminal.pickup(player)
	check(not tutorial.flags.terminal_taken and terminal.is_fixed, "Full inventory refuses native unmount and leaves the original dock intact")
	player.inventory.items.clear()
	tutorial.terminal_docked_pickup("other-terminal", player)
	check(not tutorial.flags.terminal_taken, "Other identity and empty-inventory callbacks cannot count")
	# Falling off the support then collecting is a successful acquisition, but
	# does not carry the original fixed-dock transaction evidence.
	ItemMount.release(terminal)
	terminal.pickup(player)
	check(not tutorial.flags.terminal_taken and not tutorial.inner_gate_unlocked(), "Support-loss pickup cannot open the gate")
	await frames()
	player.inventory.items.clear()
	terminal = new_terminal(world, support, tutorial.terminal_id)
	var item_state := terminal.capture_item_state()
	item_state.training_terminal.boot_started = true
	item_state.training_terminal.boot_elapsed = 6.0
	item_state.training_terminal.initialized = true
	item_state.training_terminal.dock_locked = false
	terminal.restore_item_state(item_state)
	var unread := booted.duplicate(true)
	unread.flags.boot_complete = false
	tutorial.apply_state(unread)
	terminal.interact_hold(player)
	await frames()
	check(not tutorial.flags.boot_complete, "Reading an already initialized restored Item cannot invent a missing boot transaction")
	terminal._close_ui()
	check(tutorial.apply_state(booted), "Checkpoint can restore the valid pre-pickup lesson")
	support.remove_meta("training_terminal_dock")
	tutorial._on_world_ready()
	check(support.get_meta("training_terminal_dock", "") == tutorial.terminal_id, "Checkpoint reconstruction rebinds the original static dock marker")
	terminal.pickup(player)
	check(tutorial.flags.terminal_taken and tutorial.terminal_in_inventory(player) and tutorial.inner_gate_unlocked(), "Successful native unmount of the same initialized terminal into inventory permanently opens the inner gate")
	await frames()
	player.inventory.items.clear()
	check(tutorial.inner_gate_unlocked(), "Gate remains open after terminal ownership changes again")
	player.position = Vector3(0, -0.25, -27)
	tutorial._physics_process(0.016)
	check(not tutorial.flags.workshop_entered, "Reception remains the first lesson after original terminal pickup")
	for point in [Vector3(21, -0.25, -24), Vector3(0, -4, -24), Vector3(0, 7, -24)]:
		player.position = point
		tutorial._physics_process(0.016)
		check(not tutorial.flags.workshop_entered, "Outside, below and above the workshop cannot activate its lesson")
	var reception_state := tutorial.capture()
	player.position = Vector3(0, -0.25, -24)
	check(tutorial.apply_state(reception_state), "An existing save may retain reception progress while already inside room two")
	tutorial._physics_process(0.016)
	check(tutorial.stage == 2 and tutorial.flags.workshop_entered and tutorial.terminal_page().available, "Actual body location recovers room-two teaching even when the Player origin is below the floor")
	check(COURSE.validate_state(tutorial.capture()), "Captured room crossing has a consistent schema")
	check(owner.phase == "preparing" and not tutorial.can_restart() and tutorial.can_skip() and not tutorial.departure_block_reason().is_empty(), "Missing entrance snapshots disable retry but retain skip and block unfinished departure")
	world.free()
	if failures.is_empty(): print("PASS: orientation controller native transactions and persistence")
	quit(0 if failures.is_empty() else 1)
