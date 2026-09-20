extends SceneTree
var failures: Array[String] = []
const SAVE := "res://.godot/test-outdoor-station.save"
var world: Node3D
var generator: Node
var site: Dictionary

func _init() -> void:
	_run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("STATION CHECK FAILED: ",message)

func settle() -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if DisplayServer.get_name() == "headless": OS.delay_msec(1)
		if generator.building: continue
		var all_ready: bool = not generator.active_chunks.is_empty()
		for entry in generator.active_chunks:
			if not entry.node.navigation_ready: all_ready = false
		if generator.is_processing():
			var current := floori(-generator.player.global_position.z / 150.0)
			for index in range(current - generator.profile.chunks_behind, current + generator.profile.chunks_ahead + 1):
				if not generator.active_chunks.any(func(c): return c.index == index): all_ready = false
		if all_ready:
			print("STATION terrain ready at ",generator.player.global_position)
			return
	for entry in generator.active_chunks: print("TIMEOUT NAV band=",entry.index," ready=",entry.node.navigation_ready," map=", entry.node.navigation.get_navigation_map()," worldmap=",world.get_world_3d().navigation_map)
	expect(false, "Terrain/navigation timeout")

func props_at_site() -> Array[Node]:
	var result: Array[Node] = []
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Prop and site.bounds.has_point(actor.global_position) and not actor.is_queued_for_deletion(): result.append(actor)
	return result

func walk(player: CharacterBody3D, local: Vector3) -> void:
	var target: Vector3 = site.building * local
	for frame in range(1000):
		var direction := target - player.global_position
		direction.y = 0
		if direction.length() < 0.35:
			expect(absf(player.global_position.y - target.y) < 0.5, "Walking remains supported by ground/floor")
			Input.action_release("move_forward")
			return
		player.rotation.y = atan2(-direction.x, -direction.z)
		Input.action_press("move_forward")
		await physics_frame
	Input.action_release("move_forward")
	expect(false, "Walking blocked at %s going to %s" % [player.global_position, target])

func _run() -> void:
	# Sample authored rear/side circulation and drive support on curved roads.
	for seed_value in range(30):
		var field := WorldField.new(seed_value)
		for index in [1, 4, 7, 10]:
			var planned := field.stop(index)
			expect(planned.kind == "walk_in", "v5 roadside station schedule")
			for x in [-18, 0, 18]:
				for z in [-20, -10, 0, 22]:
					var point: Vector3 = planned.building * Vector3(x, 0, z)
					expect(absf(field.height_at(point.x, point.z) - point.y) < 0.18, "Level station apron")
	world = load("res://world/test_world.tscn").instantiate()
	generator = world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = WorldProfile.new()
	generator.profile.chunks_ahead = 1
	generator.profile.chunks_behind = 1
	root.add_child(world)
	current_scene = world
	await settle()
	site = generator.field.stop(1)
	var player: CharacterBody3D = world.get_node("Player")
	player.set_physics_process(false)
	var rv: Chassis = world.get_node("NewRv/Chassis")
	rv.freeze = true
	rv.global_transform = site.building * Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 1.8, 21))
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	# Setup at the roadside parking; traversal below uses continuous real input.
	player.global_position = site.building * Vector3(0, 0.2, 16)
	player.velocity = Vector3.ZERO
	await settle()
	generator.set_process(false)
	player.set_physics_process(true)
	rv.freeze = false
	for monster in get_nodes_in_group(Groups.MONSTERS): monster.queue_free()
	var station: Node3D
	for node in generator.find_children("*", "Node3D", true, false):
		if node.get_meta("poi_id", "") == site.id: station = node
	expect(station != null and station.get_world_3d() == player.get_world_3d(), "Production walk-in building loaded in the main world")
	if station == null:
		quit(1)
		return
	for frame in range(100): await physics_frame
	var original := props_at_site()
	expect(original.size() >= 4, "Production marker loot generated")
	for item in original: expect(item.global_position.y > site.building.origin.y - 0.3, "Loot supported")
	var navmap := world.get_world_3d().navigation_map
	print("NAV MAP iter=", NavigationServer3D.map_get_iteration_id(navmap), " player=", player.global_position, " closest=", NavigationServer3D.map_get_closest_point(navmap, player.global_position))
	for entry in generator.active_chunks: print("NAV REGION ",entry.index," polygons=",entry.node.navigation.navigation_mesh.get_polygon_count(), " ready=",entry.node.navigation_ready)
	for local in [Vector3(0, 0, -18), Vector3(6.5, 0, -10.5)]:
		var target: Vector3 = site.building * local
		var path := NavigationServer3D.map_get_path(navmap, player.global_position, target, true)
		print("STATION NAV target=", target, " end=", path[-1] if not path.is_empty() else Vector3.ZERO, " count=", path.size())
		expect(path.size() >= 2 and path[-1].distance_to(target) < 1, "Production navigation reaches store/service area")
	for point in [Vector3(0,0,-8), Vector3(0,0,-18), Vector3(12,0,-18), Vector3(12,0,0), Vector3(6.5,0,0), Vector3(6.5,0,-10.5), Vector3(0,0,-10.5), Vector3(0,0,-4.7), Vector3(-5.5,0,-4.7)]:
		await walk(player, point)
	var camera: Camera3D = player.get_node("Camera3D")
	camera.look_at(site.building * Vector3(-5.5,1.35,-6.1))
	for frame in range(10): await physics_frame
	var before: int = player.inventory.items.size()
	Input.action_press("interact")
	for frame in range(8): await physics_frame
	Input.action_release("interact")
	for frame in range(10): await physics_frame
	expect(player.inventory.items.size() == before + 1, "Production interaction ray picks up station fuel")
	await walk(player, Vector3(0,0,-4.7))
	await walk(player, Vector3(0,0,17))
	expect(rv.store_player_item(player, player.inventory.items.size() - 1), "Station fuel carried back into RV storage")
	# A loose item brought from elsewhere must be owned by the dormant site too.
	var brought: Prop = world.get_node("Scrap")
	brought.global_position = site.building * Vector3(2, 0.4, -8)
	brought.linear_velocity = Vector3.ZERO
	brought.freeze = true
	var ids: Array[String] = []
	for prop in props_at_site(): ids.append(prop.persistent_id)
	ids.append(brought.persistent_id)
	# Leave far enough to retire the owner band through the production streamer.
	player.set_physics_process(false)
	player.global_position = site.road.origin + Vector3(0, 2, -900)
	generator.set_process(true)
	await settle()
	for frame in range(15): await process_frame
	await settle()
	expect(not generator.outdoor_sites[site.id].loaded, "Leaving unloads and snapshots station")
	expect(generator.outdoor_sites[site.id].actors.size() == ids.size(), "Only remaining loot is dormant")
	generator.set_process(false)
	var checkpoint := root.get_node("Checkpoint")
	expect(checkpoint.save_world(world, SAVE), "Dormant station checkpoint writes")
	var saved: Dictionary = checkpoint.read_checkpoint(SAVE)
	expect(not saved.is_empty(), "Dormant actor save validates")
	var bad := saved.duplicate(true)
	bad.outdoor_sites[site.id].content_version = 99
	expect(not checkpoint.validation_error(bad).is_empty(), "Unsupported station layout rejected")
	# Actual disk reload recreates the production scene and active/dormant ownership.
	expect(await checkpoint.load_world(world, SAVE), "Checkpoint restores main world")
	world = current_scene
	generator = world.get_node("WorldGenerator")
	player = world.get_node("Player")
	player.set_physics_process(false)
	player.global_position = site.building * Vector3(0, 1, 21)
	await settle()
	for frame in range(15): await process_frame
	await settle()
	generator.set_process(false)
	var returned: Array[String] = []
	for prop in props_at_site(): returned.append(prop.persistent_id)
	ids.sort(); returned.sort()
	expect(ids == returned, "Return after disk restore preserves exact remaining identities without duplicates")
	expect(generator.protected_bands(player.global_position).size() >= 3, "Station pins owner and neighbouring terrain")
	# An active station save must not also contain dormant actor copies.
	expect(checkpoint.save_world(world, SAVE + ".active"), "Active station checkpoint writes")
	var active: Dictionary = checkpoint.read_checkpoint(SAVE + ".active")
	expect(active.outdoor_sites[site.id].loaded and active.outdoor_sites[site.id].actors.is_empty(), "Active loot belongs only to main actors")
	print("STATION remaining_ids=", returned.size(), " station=", site.building.origin)
	await settle()
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: production station terrain, walking, navigation, pickup, streaming return and disk persistence")
	else:
		for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


