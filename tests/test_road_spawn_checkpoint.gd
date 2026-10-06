extends SceneTree
const WAIT = preload("res://tests/support/test_wait.gd")
const SAVE_PATH := "res://.godot/test-road-spawn-checkpoint.save"
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func settle(world: Node) -> bool:
	return await WAIT.generator_idle(self, world.get_node("WorldGenerator")) and await WAIT.retired_candidates(self, root.get_node("Checkpoint"))

func monsters(world: Node3D) -> Array:
	return get_nodes_in_group(Groups.MONSTERS).filter(func(n): return n is Monster and WorldEntities.same_world(world, n) and not n.is_queued_for_deletion() and not n.is_dead)

func run() -> void:
	var checkpoint: Node = root.get_node("Checkpoint")
	var world: Node3D = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = generator.profile.duplicate()
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 0
	root.add_child(world)
	current_scene = world
	if not await world.wait_for_play() or not await settle(world):
		check(false, "Production checkpoint fixture becomes ready")
		quit(1)
		return
	generator.set_process(false)
	var band := -1
	var plan: Dictionary
	for candidate in range(3, 100):
		var data := RoadSpawns.plan(generator.field, candidate)
		# Isolate the road actors from authored site actors in this fixture.
		if not data.monsters.is_empty() and generator.field.stops_in_band(candidate).is_empty():
			band = candidate
			plan = data
			break
	check(band >= 3, "Fixture finds a road-only encounter")
	if band < 3: world.free(); quit(1); return
	world.get_node("StartRun").restore({"version": 1, "phase": "sealed"})
	var anchor: Vector3 = generator.field.road_frame((band + 0.5) * 150.0).origin
	world.get_node("Player").global_position = anchor + Vector3(0, 2, 0)
	world.get_node("Player").set_physics_process(false)
	var chassis: Chassis = world.get_node("NewRv/Chassis")
	chassis.freeze = true
	chassis.global_position = anchor + Vector3(0, 2, 20)
	var destroyed_id := TreeImpact.forest_id(band, 0)
	generator.destroyed_trees[destroyed_id] = true
	await generator._spawn_band(band, true)
	if not await settle(world):
		check(false, "Road encounter navigation settles")
		world.free()
		quit(1)
		return
	for entry in generator.active_chunks.duplicate():
		if entry.index != band: generator.retire_band(entry)
	for monster: Monster in monsters(world): monster.process_mode = Node.PROCESS_MODE_DISABLED
	check(monsters(world).size() == plan.monsters.size(), "Production road encounter spawns exactly its planned Rakers")
	check(checkpoint.save_world(world, SAVE_PATH), "v8 road checkpoint writes")
	var before: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	check(before.get("version") == 5 and before.get("generation_version") == 8, "Checkpoint uses v5 while retaining v8 generation")
	check(band in before.get("generated_bands", []), "Road band is marked generated")
	check(before.get("destroyed_trees", {}).get(destroyed_id, false), "v8 road checkpoint preserves the destroyed-tree ledger")
	if not await checkpoint.load_world(world, SAVE_PATH):
		check(false, "v8 road checkpoint reload succeeds")
		quit(1)
		return
	world = current_scene
	check(world.get_node("Player").global_transform.is_equal_approx(before.player.transform), "F9 world transfer preserves saved road player pose")
	check(floori(-world.get_node("Player").global_position.z / 150.0) == band, "F9 keeps player in the saved encounter band")
	if not await settle(world):
		check(false, "Restored road encounter settles")
		quit(1)
		return
	generator = world.get_node("WorldGenerator")
	generator.set_process(false)
	world.get_node("Player").set_physics_process(false)
	check(monsters(world).size() == plan.monsters.size(), "F9 restores living Rakers without duplicate rolls")
	check(generator.destroyed_trees.get(destroyed_id, false) and generator.field.destroyed_trees.get(destroyed_id, false), "F9 restores the shared destroyed-tree ledger before chunk generation")
	for monster: Monster in monsters(world):
		monster.take_damage(monster.current_health + 1.0)
	await process_frame
	check(monsters(world).is_empty(), "Killed road encounter has no live actors")
	check(checkpoint.save_world(world, SAVE_PATH), "Cleared encounter checkpoint writes")
	var cleared: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	if not await checkpoint.load_world(world, SAVE_PATH):
		check(false, "Cleared encounter checkpoint reload succeeds")
		quit(1)
		return
	world = current_scene
	check(world.get_node("Player").global_transform.is_equal_approx(cleared.player.transform), "Cleared checkpoint retains player road pose after transfer")
	if not await settle(world):
		check(false, "Cleared restored terrain settles")
		quit(1)
		return
	generator = world.get_node("WorldGenerator")
	generator.set_process(false)
	world.get_node("Player").set_physics_process(false)
	check(monsters(world).is_empty(), "F9 does not resurrect killed road Rakers")
	var old_entry: Dictionary
	for entry in generator.active_chunks:
		if entry.index == band: old_entry = entry
	check(not old_entry.is_empty(), "Encounter band restored")
	if not old_entry.is_empty():
		generator.retire_band(old_entry)
		await process_frame
		await generator._spawn_band(band, true)
		if not await settle(world): check(false, "Revisited road navigation settles")
		check(monsters(world).is_empty(), "Backtracking/rebuilding cleared band does not resurrect Rakers")
	world.free()
	await process_frame
	if failures.is_empty(): print("PASS: production v8 road checkpoints, living actor restore and cleared encounter backtracking")
	quit(0 if failures.is_empty() else 1)
