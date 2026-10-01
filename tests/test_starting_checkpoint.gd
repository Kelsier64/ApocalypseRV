extends SceneTree
## Production scene selection and real checkpoint transactions across the opening.
const SAVE_PATH := "res://.godot/test-starting-checkpoint.save"
const WAIT = preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func settle(world: Node) -> bool:
	# Keep the physical actor settling interval used by this checkpoint fixture.
	for i in range(90): await physics_frame
	if not await WAIT.generator_idle(self, world.get_node("WorldGenerator")):
		check(false, "Checkpoint fixture terrain/navigation did not settle within 60 seconds")
		return false
	if not await WAIT.retired_candidates(self, root.get_node("Checkpoint")):
		check(false, "Checkpoint candidate retirement timed out within 60 seconds")
		return false
	return true

func wait_phase(world: Node, phase: String) -> bool:
	return await WAIT.until(self, func() -> bool:
		return is_instance_valid(world) and world.get_node("StartRun").phase == phase,
		15000, true)

func _run() -> void:
	var checkpoint: Node = root.get_node("Checkpoint")
	var world: Node3D = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = generator.profile.duplicate()
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	root.add_child(world)
	current_scene = world
	if not await world.wait_for_play():
		check(false, "Shelter checkpoint fixture becomes ready")
		quit(1)
		return
	if not await settle(world):
		quit(1)
		return
	var flashlight: Prop
	for actor in world.get_node("WorldEntities").get_children():
		if actor.scene_file_path == "res://props/flashlight.tscn": flashlight = actor
	check(is_instance_valid(flashlight), "Fresh shelter provides a flashlight")
	if is_instance_valid(flashlight): flashlight.interact(world.get_node("Player"))
	await process_frame
	check(checkpoint.save_world(world, SAVE_PATH), "Preparation checkpoint writes")
	var prepared: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	if prepared.is_empty(): quit(1); return
	check(prepared.generation_version == 8, "New production checkpoint records v8")
	check(prepared.world_id == "shelter" and prepared.start_state.phase == "preparing", "Checkpoint identifies production and preparation")
	check(prepared.player.items.size() == 1, "Picked item belongs only to player inventory")
	for invalid in ["opening", "closing", "unknown"]:
		var bad := prepared.duplicate(true)
		bad.start_state.phase = invalid
		check(checkpoint.validation_error(bad) == "start_state.phase", "Reject unstable or unknown phase: " + invalid)
	var unknown := prepared.duplicate(true)
	unknown.world_id = "res://arbitrary.tscn"
	check(checkpoint.validation_error(unknown) == "world_id", "Save cannot choose an arbitrary scene")
	var missing := prepared.duplicate(true)
	missing.erase("start_state")
	check(not checkpoint.validation_error(missing).is_empty(), "Production requires an explicit start state")
	if not await checkpoint.load_world(world, SAVE_PATH):
		check(false, "Preparation reload transaction succeeds")
		quit(1)
		return
	world = current_scene
	if not await settle(world):
		quit(1)
		return
	check(world.scene_file_path == "res://world/main_world.tscn", "Reload uses production world")
	check(world.get_node("StartRun").phase == "preparing" and not world.get_node("WorldClock").running, "Reload keeps preparation frozen")
	check(checkpoint.save_world(world, SAVE_PATH), "Reloaded preparation can save")
	var again: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	check(again.player.items == prepared.player.items, "Inventory identities survive reload")
	check(again.actors.size() == prepared.actors.size(), "Reload does not duplicate remaining supplies or equipment")
	var run: Node = world.get_node("StartRun")
	var button: Node = run.shelter.get_node("GarageButton")
	button.interact(world.get_node("Player"))
	check(not checkpoint.save_world(world, SAVE_PATH), "Opening animation rejects saving")
	if not await wait_phase(world, "started"):
		check(false, "Opening reaches stable started phase within 15 seconds")
		quit(1)
		return
	check(checkpoint.save_world(world, SAVE_PATH), "Started checkpoint writes")
	if not await checkpoint.load_world(world, SAVE_PATH):
		check(false, "Started checkpoint reloads")
		quit(1)
		return
	world = current_scene
	if not await settle(world):
		quit(1)
		return
	run = world.get_node("StartRun")
	check(run.phase == "started" and world.get_node("WorldClock").running, "Reload keeps open gate and running clock")
	# Position only for checkpoint setup. Wheel-powered departure is tested separately.
	for rv in get_nodes_in_group(Groups.CHASSIS):
		if WorldEntities.same_world(world, rv):
			rv.global_position = run.shelter.to_global(Vector3(0, 1.8, 42))
			rv.linear_velocity = Vector3.ZERO
			rv.angular_velocity = Vector3.ZERO
	world.get_node("Player").global_position = run.shelter.to_global(Vector3(5, 1, 42))
	if not await wait_phase(world, "sealed"):
		check(false, "Departure reaches sealed phase within 15 seconds")
		quit(1)
		return
	if not await settle(world):
		quit(1)
		return
	check(checkpoint.save_world(world, SAVE_PATH), "Sealed checkpoint writes")
	if not await checkpoint.load_world(world, SAVE_PATH):
		check(false, "Sealed checkpoint reloads")
		quit(1)
		return
	world = current_scene
	if not await settle(world):
		quit(1)
		return
	run = world.get_node("StartRun")
	check(run.phase == "sealed", "Reload preserves irreversible closure")
	run.shelter.get_node("GarageButton").interact(world.get_node("Player"))
	check(run.phase == "sealed", "Reloaded button cannot reopen sealed garage")
	# Capture a real v7 world, including versioned site IDs and terrain seeds.
	var previous: Node3D = load("res://world/main_world.tscn").instantiate()
	var previous_generator: Node = previous.get_node("WorldGenerator")
	previous_generator.world_seed = 42
	previous_generator.profile = previous_generator.profile.duplicate()
	previous_generator.profile.generation_version = 7
	previous_generator.profile.chunks_ahead = 0
	previous_generator.profile.chunks_behind = 1
	root.add_child(previous)
	if not await previous.wait_for_play() or not await settle(previous):
		check(false, "Pinned v7 shelter fixture becomes ready")
		quit(1)
		return
	check(checkpoint.save_world(previous, SAVE_PATH + ".v7"), "Existing v7 shelter checkpoint writes")
	previous.free()
	if not await checkpoint.load_world(world, SAVE_PATH + ".v7"):
		check(false, "v7 shelter checkpoint reload transaction succeeds")
		quit(1)
		return
	world = current_scene
	if not await settle(world):
		quit(1)
		return
	var restored_generator: Node = world.get_node("WorldGenerator")
	check(restored_generator.profile.generation_version == 7 and restored_generator.field.stop(0).id.begins_with("v7:"), "v7 reload retains original generation and site IDs")
	for entry in restored_generator.active_chunks:
		check(entry.node.road_spawns.is_empty(), "v7 reload does not add v8 road content")
	# A real legacy fixture yields an old checkpoint without the new optional fields.
	var legacy: Node3D = load("res://world/test_world.tscn").instantiate()
	legacy.get_node("WorldGenerator").profile = WorldProfile.new()
	legacy.get_node("WorldGenerator").profile.chunks_ahead = 0
	legacy.get_node("WorldGenerator").profile.chunks_behind = 0
	root.add_child(legacy)
	if not await legacy.wait_for_play():
		check(false, "Legacy fixture becomes ready")
		quit(1)
		return
	if not await settle(legacy):
		quit(1)
		return
	check(checkpoint.save_world(legacy, SAVE_PATH + ".legacy"), "Legacy fixture writes")
	var old: Dictionary = checkpoint.read_checkpoint(SAVE_PATH + ".legacy")
	old.erase("world_id")
	check(checkpoint.write_checkpoint(SAVE_PATH + ".legacy", old), "Old-format fixture writes")
	legacy.free()
	if not await checkpoint.load_world(world, SAVE_PATH + ".legacy"):
		check(false, "Production session can load old checkpoint")
		quit(1)
		return
	world = current_scene
	if not await settle(world):
		quit(1)
		return
	check(world.scene_file_path == "res://world/test_world.tscn" and not world.has_node("StartRun"), "Legacy save restores original world without intro or supplies")
	check(world.get_node("WorldGenerator").profile.generation_version == 6, "Legacy generation remains v6")
	world.free()
	if failures.is_empty(): print("PASS: production checkpoint phases, actor identities, trusted scenes and legacy reload")
	quit(0 if failures.is_empty() else 1)
