extends "res://tests/test_outdoor_gas_station.gd"
## Reuses production-world readiness and walking helpers, not station fixtures.
const MINOR_SAVE := "res://.godot/test-minor-site.save"

func _run() -> void:
	# Persistence tests isolate AI; encounters/traversal are tested separately.
	node_added.connect(func(node):
		if node is Monster: node.process_mode = Node.PROCESS_MODE_DISABLED)
	var chosen_seed := -1
	for seed_value in range(100):
		var candidate := WorldField.new(seed_value)
		var planned := candidate.minor_site(0)
		if not planned.is_empty() and candidate.rng_for(0, "minor_enemies").randi_range(0, 2) == 2:
			chosen_seed = seed_value
			site = planned
			break
	expect(chosen_seed >= 0, "Found deterministic two-enemy fixture")
	world = load("res://world/test_world.tscn").instantiate()
	generator = world.get_node("WorldGenerator")
	generator.world_seed = chosen_seed
	generator.profile = WorldProfile.new()
	generator.profile.chunks_ahead = 1
	generator.profile.chunks_behind = 1
	var band := floori(float(site.s) / 150)
	generator.restore_bands.assign(range(band - 1, band + 2))
	world.get_node("Player").position = site.building * Vector3(0, 1, 20)
	root.add_child(world)
	current_scene = world
	world.get_node("Player").set_physics_process(false)
	await settle()
	generator.set_process(false)
	var player: CharacterBody3D = world.get_node("Player")
	player.set_physics_process(false)
	var monsters: Array[Monster] = []
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Monster and site.bounds.has_point(actor.global_position):
			monsters.append(actor)
			actor.set_physics_process(false)
	expect(monsters.size() == 2, "Production owner spawns configured enemies")
	if monsters.size() != 2:
		world.free()
		quit(1)
		return
	monsters[0].take_damage(7)
	var health: float = monsters[0].current_health
	monsters[1].take_damage(10000)
	for frame in range(30): await physics_frame
	var loot := props_at_site()
	expect(loot.size() >= 2, "Production marker loot")
	var picked_id: String = loot[0].persistent_id
	# Real interaction while in reach, then freeze the remaining objects for exact comparisons.
	player.global_position = loot[0].global_position + site.building.basis.z * 1.15
	player.global_position.y = site.building.origin.y + 0.25
	player.camera.look_at(loot[0].global_position)
	player.set_physics_process(true)
	for frame in range(12): await physics_frame
	print("MINOR_PICKUP player=", player.global_position, " item=", loot[0].global_position, " ray=", player.get_node("Camera3D/InteractRay").get_collider())
	Input.action_press("interact")
	for frame in range(12): await physics_frame
	Input.action_release("interact")
	player.set_physics_process(false)
	expect(player.inventory.items.size() == 1, "Real roadside pickup enters inventory")
	var moved: Prop = props_at_site()[0]
	moved.global_position = site.building * Vector3(-8, 0.6, 5)
	moved.freeze = true
	var moved_id := moved.persistent_id
	var moved_pose := moved.global_transform
	var brought: Prop = world.get_node("Scrap")
	brought.global_position = site.building * Vector3(8, 0.6, 5)
	brought.freeze = true
	var ids: Array[String] = []
	for prop in props_at_site():
		ids.append(prop.persistent_id)
		prop.freeze = true
	ids.append(brought.persistent_id)
	expect(picked_id not in ids, "Picked item no longer on ground")
	player.global_position = site.road.origin + Vector3(0, 2, -1050)
	generator.set_process(true)
	await settle()
	for frame in range(20): await process_frame
	await settle()
	generator.set_process(false)
	expect(not generator.outdoor_sites[site.id].loaded, "Minor owner unloads")
	var dormant: Array = generator.outdoor_sites[site.id].actors
	expect(dormant.filter(func(a): return a.kind == "monster").size() == 1, "Dead enemy excluded from dormant state")
	expect(dormant.filter(func(a): return a.kind == "prop").size() == ids.size(), "Remaining and brought loot saved once")
	var checkpoint := root.get_node("Checkpoint")
	expect(checkpoint.save_world(world, MINOR_SAVE), "Write v6 dormant checkpoint")
	var saved: Dictionary = checkpoint.read_checkpoint(MINOR_SAVE)
	expect(saved.get("generation_version") == 6 and saved.get("version") == 3, "v6 uses existing checkpoint format")
	expect(await checkpoint.load_world(world, MINOR_SAVE), "Disk restore succeeds")
	world = current_scene
	generator = world.get_node("WorldGenerator")
	player = world.get_node("Player")
	player.set_physics_process(false)
	player.global_position = site.building * Vector3(0, 1, 20)
	await settle()
	for frame in range(20): await process_frame
	await settle()
	generator.set_process(false)
	var returned: Array[String] = []
	for prop in props_at_site():
		returned.append(prop.persistent_id)
		if prop.persistent_id == moved_id: expect(prop.global_transform.is_equal_approx(moved_pose), "Moved item transform restored")
	ids.sort()
	returned.sort()
	expect(ids == returned, "Exact remaining identities, no replenishment or duplicates")
	var live := 0
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Monster and site.bounds.has_point(actor.global_position):
			live += 1
			actor.set_physics_process(false)
			expect(is_equal_approx(actor.current_health, health), "Enemy damage persists")
	expect(live == 1, "Killed enemy does not respawn")
	expect(generator.protected_bands(player.global_position).size() >= 3, "Independent minor site pins neighbours")
	expect(checkpoint.save_world(world, MINOR_SAVE + ".active"), "Write active minor checkpoint")
	var active: Dictionary = checkpoint.read_checkpoint(MINOR_SAVE + ".active")
	if not active.is_empty(): expect(active.outdoor_sites[site.id].loaded and active.outdoor_sites[site.id].actors.is_empty(), "No dormant copies in active checkpoint")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: production v6 pickup, brought/moved loot, enemy damage/death, streaming and disk round trip")
	for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
