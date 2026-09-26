extends "res://tests/test_outdoor_gas_station.gd"
## Production minor courtyard crossing the 900m terrain seam.
func _run() -> void:
	node_added.connect(func(node):
		if node is Monster: node.process_mode = Node.PROCESS_MODE_DISABLED)
	var field := WorldField.new(2)
	site = field.minor_site(0)
	expect(site.bounds.position.z < -900 and site.bounds.end.z > -900, "Fixture crosses a band seam")
	world = load("res://world/test_world.tscn").instantiate()
	generator = world.get_node("WorldGenerator")
	generator.world_seed = 2
	generator.profile = WorldProfile.new()
	generator.profile.chunks_ahead = 1
	generator.profile.chunks_behind = 1
	generator.restore_bands.assign([5, 6, 7])
	var road_start := field.road_frame(site.s - 35).origin
	world.get_node("Player").position = road_start + Vector3.UP
	root.add_child(world)
	current_scene = world
	var player: CharacterBody3D = world.get_node("Player")
	player.set_physics_process(false)
	await settle()
	generator.set_process(false)
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Monster: actor.free()
	var map := world.get_world_3d().navigation_map
	for local in [Vector3(-5,0,5.2), Vector3(-5,0,1.2), Vector3(5,0,1.2), Vector3(5,0,5.2)]:
		var target: Vector3 = site.building * local
		var path := NavigationServer3D.map_get_path(map, road_start, target, true)
		expect(path.size() >= 2 and path[-1].distance_to(target) < 0.8, "Road-to-loot navigation crosses production seam")
	player.set_physics_process(true)
	var entry: Vector3 = site.road * Vector3(site.side * 12, 0, 14)
	await walk(player, site.building.affine_inverse() * entry)
	await walk(player, site.building.affine_inverse() * site.frame.origin)
	await walk(player, Vector3(0,0,8))
	await walk(player, Vector3(0,0,5.2))
	await walk(player, Vector3(-5,0,5.2))
	await walk(player, Vector3(0,0,5.2))
	await walk(player, Vector3(0,0,8))
	await walk(player, site.building.affine_inverse() * site.frame.origin)
	await walk(player, site.building.affine_inverse() * entry)
	await walk(player, site.building.affine_inverse() * road_start)
	expect(generator.protected_bands(site.building.origin).has(5), "Minor site protects neighbouring approach terrain")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: minor POI production seam navigation, real road-to-loot walk and return")
	for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
