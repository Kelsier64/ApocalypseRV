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

func road_barrels(world: Node3D) -> Array:
	return WorldEntities.get_container(world).get_children().filter(func(n): return n is OilBarrel and n.persistent_id.begins_with("road:") and not n.is_destroyed and not n.is_queued_for_deletion())

func same_world_chassis(world: Node3D) -> Chassis:
	for node in get_nodes_in_group(Groups.CHASSIS):
		if node is Chassis and WorldEntities.same_world(world, node): return node
	return null

func species(world: Node3D) -> Array[String]:
	var result: Array[String] = []
	for monster: Monster in monsters(world): result.append(monster.scene_file_path)
	result.sort()
	return result

func freeze_fixture(world: Node3D) -> void:
	world.get_node("WorldGenerator").set_process(false)
	world.get_node("Player").set_physics_process(false)
	for monster: Monster in monsters(world): monster.process_mode = Node.PROCESS_MODE_DISABLED
	for barrel: OilBarrel in road_barrels(world):
		barrel.freeze = true
		barrel.process_mode = Node.PROCESS_MODE_DISABLED

func run() -> void:
	for version in [8, 9]: await run_version(version)
	if failures.is_empty(): print("PASS: v8/v9 road checkpoints, mixed species, ordinary barrel restore and cleared encounter backtracking")
	quit(0 if failures.is_empty() else 1)

func run_version(version: int) -> void:
	var checkpoint: Node = root.get_node("Checkpoint")
	var world: Node3D = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = generator.profile.duplicate()
	generator.profile.generation_version = version
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 0
	root.add_child(world)
	current_scene = world
	if not await world.wait_for_play() or not await settle(world):
		check(false, "Production checkpoint fixture becomes ready")
		if is_instance_valid(world): world.free()
		await process_frame
		return
	generator.set_process(false)
	WorldEntities.get_container(world).child_entered_tree.connect(freeze_actor)
	var band := -1
	var plan: Dictionary
	for candidate in range(3, 1500):
		var data := RoadSpawns.plan(generator.field, candidate)
		# Isolate the road actors from authored site actors in this fixture.
		if not data.monsters.is_empty() and generator.field.stops_in_band(candidate).is_empty() and (version == 8 or (RoadSpawns.BARREL_MAN_SCENE in data.monster_scenes and RoadSpawns.RAKER_SCENE in data.monster_scenes and not data.get("barrels", []).is_empty())):
			band = candidate
			plan = data
			break
	check(band >= 3, "Fixture finds a road-only encounter")
	if band < 3: world.free(); await process_frame; return
	world.get_node("StartRun").restore({"version": 1, "phase": "sealed"})
	var anchor: Vector3 = generator.field.road_frame((band + 0.5) * 150.0).origin
	world.get_node("Player").global_position = anchor + Vector3(0, 2, 0)
	world.get_node("Player").set_physics_process(false)
	var chassis := same_world_chassis(world)
	check(chassis != null, "Production fixture owns a same-world Chassis")
	if chassis == null: world.free(); await process_frame; return
	chassis.freeze = true
	chassis.global_position = anchor + Vector3(0, 2, 20)
	var destroyed_id := TreeImpact.forest_id(band, 0)
	generator.destroyed_trees[destroyed_id] = true
	await generator._spawn_band(band, true)
	if not await settle(world):
		check(false, "Road encounter navigation settles")
		if is_instance_valid(world): world.free()
		await process_frame
		return
	for entry in generator.active_chunks.duplicate():
		if entry.index != band: generator.retire_band(entry)
	freeze_fixture(world)
	var expected_species: Array[String] = []
	expected_species.assign(plan.monster_scenes)
	expected_species.sort()
	check(species(world) == expected_species, "Production road actors preserve independently planned Raker and BarrelMan species")
	var barrel_id := ""
	var moved_pose := Transform3D.IDENTITY
	if version >= 9:
		check(road_barrels(world).size() == plan.barrels.size(), "Production creates the independently planned ordinary barrels")
		if not road_barrels(world).is_empty():
			var barrel: OilBarrel = road_barrels(world)[0]
			barrel_id = barrel.persistent_id
			barrel.global_position = anchor + Vector3(60, 2, 0)
			barrel.rotation.y = 0.7
			moved_pose = barrel.global_transform
	check(monsters(world).size() == plan.monsters.size(), "Production road encounter spawns exactly its planned Rakers")
	check(checkpoint.save_world(world, SAVE_PATH), "Versioned road checkpoint writes")
	var before: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	check(before.get("version") == 5 and before.get("generation_version") == version, "Checkpoint uses v5 while retaining its generation version")
	check(band in before.get("generated_bands", []), "Road band is marked generated")
	check(before.get("destroyed_trees", {}).get(destroyed_id, false), "Versioned road checkpoint preserves the destroyed-tree ledger")
	if not await checkpoint.load_world(world, SAVE_PATH):
		check(false, "Versioned road checkpoint reload succeeds")
		if is_instance_valid(world): world.free()
		await process_frame
		return
	world = current_scene
	check(world.get_node("Player").global_transform.is_equal_approx(before.player.transform), "F9 world transfer preserves saved road player pose")
	check(floori(-world.get_node("Player").global_position.z / 150.0) == band, "F9 keeps player in the saved encounter band")
	if not await settle(world):
		check(false, "Restored road encounter settles")
		if is_instance_valid(world): world.free()
		await process_frame
		return
	generator = world.get_node("WorldGenerator")
	generator.set_process(false)
	world.get_node("Player").set_physics_process(false)
	freeze_fixture(world)
	check(monsters(world).size() == plan.monsters.size(), "F9 restores living road monsters without duplicate rolls")
	check(species(world) == expected_species, "F9 preserves mixed road monster species")
	var consumed_barrel_ids: Array[String] = []
	if version >= 9:
		var restored_barrels := road_barrels(world)
		check(restored_barrels.size() == plan.barrels.size(), "F9 restores ordinary barrels exactly once")
		var moved := restored_barrels.filter(func(n): return n.persistent_id == barrel_id)
		check(moved.size() == 1 and moved[0].global_transform.is_equal_approx(moved_pose), "F9 restores a moved ordinary barrel pose and stable identity")
		# Loose road items sleep by band rather than being rerolled on reentry.
		var live_entry: Dictionary
		for entry in generator.active_chunks:
			if entry.index == band: live_entry = entry
		if not live_entry.is_empty():
			generator.retire_band(live_entry)
			await process_frame
			check(road_barrels(world).is_empty(), "Unloaded road barrels enter dormant item storage")
			await generator._spawn_band(band, true)
			if not await settle(world): check(false, "Revisited live barrel navigation settles")
			freeze_fixture(world)
			moved = road_barrels(world).filter(func(n): return n.persistent_id == barrel_id)
			check(road_barrels(world).size() == plan.barrels.size() and moved.size() == 1 and moved[0].global_transform.is_equal_approx(moved_pose), "Reentry restores dormant moved barrel without rerolling its birth pose")
		# Exercise the production impact hook with a qualifying closing speed;
		# frozen fixture bodies deliberately do not run wheel/contact dynamics.
		# Keep the blast far from the fixture player and vehicle.
		var restored_chassis := same_world_chassis(world)
		check(restored_chassis != null, "Reloaded fixture owns a same-world Chassis")
		if restored_chassis != null:
			var saved_linear := restored_chassis.linear_velocity
			var saved_angular := restored_chassis.angular_velocity
			restored_chassis._impact_age = 0.0
			restored_chassis.angular_velocity = Vector3.ZERO
			for barrel: OilBarrel in road_barrels(world):
				barrel.global_position = anchor + Vector3(60, 2, 0)
				barrel.linear_velocity = Vector3.ZERO
				barrel.angular_velocity = Vector3.ZERO
				restored_chassis.linear_velocity = Vector3.RIGHT * 5.9
				check(not barrel.receive_vehicle_body_contact(restored_chassis, Vector3.RIGHT, barrel.global_position), "Below-threshold road barrel contact remains live")
				check(not WorldActorSnapshot.capture(barrel).is_empty(), "Unconsumed road barrel remains available to persistence")
				restored_chassis.linear_velocity = Vector3.RIGHT * 7.0
				check(barrel.receive_vehicle_body_contact(restored_chassis, Vector3.RIGHT, barrel.global_position), "Road barrel accepts a qualifying high-speed closing impact")
				check(barrel.is_destroyed and WorldActorSnapshot.capture(barrel).is_empty(), "Qualified impact excludes consumed barrel from snapshots before deferred removal")
				consumed_barrel_ids.append(barrel.persistent_id)
			restored_chassis.linear_velocity = saved_linear
			restored_chassis.angular_velocity = saved_angular
		await process_frame
		check(road_barrels(world).is_empty(), "Exploded ordinary road barrels leave the live encounter")
	check(generator.destroyed_trees.get(destroyed_id, false) and generator.field.destroyed_trees.get(destroyed_id, false), "F9 restores the shared destroyed-tree ledger before chunk generation")
	for monster: Monster in monsters(world):
		monster.take_damage(monster.current_health + 1.0)
	await process_frame
	check(monsters(world).is_empty(), "Killed road encounter has no live actors")
	check(checkpoint.save_world(world, SAVE_PATH), "Cleared encounter checkpoint writes")
	var cleared: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	var saved_items: Array = cleared.get("actors", []).duplicate()
	for records: Array in cleared.get("dormant_items", {}).values(): saved_items.append_array(records)
	for consumed_id: String in consumed_barrel_ids:
		check(not saved_items.any(func(record: Dictionary) -> bool: return record.get("state", {}).get("id", "") == consumed_id), "Cleared checkpoint excludes consumed barrel identity from active and dormant records")
	if not await checkpoint.load_world(world, SAVE_PATH):
		check(false, "Cleared encounter checkpoint reload succeeds")
		if is_instance_valid(world): world.free()
		await process_frame
		return
	world = current_scene
	check(world.get_node("Player").global_transform.is_equal_approx(cleared.player.transform), "Cleared checkpoint retains player road pose after transfer")
	if not await settle(world):
		check(false, "Cleared restored terrain settles")
		if is_instance_valid(world): world.free()
		await process_frame
		return
	generator = world.get_node("WorldGenerator")
	generator.set_process(false)
	world.get_node("Player").set_physics_process(false)
	freeze_fixture(world)
	check(monsters(world).is_empty(), "F9 does not resurrect killed road monsters")
	check(road_barrels(world).is_empty(), "F9 does not respawn exploded ordinary road barrels")
	var old_entry: Dictionary
	for entry in generator.active_chunks:
		if entry.index == band: old_entry = entry
	check(not old_entry.is_empty(), "Encounter band restored")
	if not old_entry.is_empty():
		generator.retire_band(old_entry)
		await process_frame
		await generator._spawn_band(band, true)
		if not await settle(world): check(false, "Revisited road navigation settles")
		check(monsters(world).is_empty(), "Backtracking/rebuilding cleared band does not resurrect monsters")
		check(road_barrels(world).is_empty(), "Backtracking does not respawn consumed ordinary road barrels")
	world.free()
	await process_frame

func freeze_actor(actor: Node) -> void:
	if actor is Monster: actor.process_mode = Node.PROCESS_MODE_DISABLED
	elif actor is OilBarrel:
		actor.freeze = true
		actor.process_mode = Node.PROCESS_MODE_DISABLED
