extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(okay: bool, message: String) -> void:
	if not okay and failures.size() < 30:
		failures.append(message)
		push_error("FAIL: " + message)

func _run() -> void:
	var legacy_profile := WorldProfile.new()
	legacy_profile.generation_version = 3
	var legacy := WorldField.new(42, legacy_profile)
	check(legacy_profile.terrain_half_width == 225 and legacy.stop(0).building.origin.is_equal_approx(Vector3(135, 6, -45)), "Saved v3 retains original strip and entrance")
	check(ExplorationSite.route_length(legacy.stop(0)) < 200 and legacy.stop(0).id == "v3:42:stop:0", "Saved v3 route and POI identity unchanged")
	for seed_value in range(100):
		var field := WorldField.new(seed_value)
		var repeat := WorldField.new(seed_value)
		for index in range(9):
			var site := field.stop(index)
			check(site == repeat.stop(index), "Deterministic complete site")
			if not site.has("route"):
				check(field.loot_plan(index).size() in [1, 2], "Small supply budget")
				continue
			check(ExplorationSite.route_length(site) >= 480 and ExplorationSite.route_length(site) <= 580, "Extended forest walking distance")
			check(float(field.road_query(site.building.origin.x, site.building.origin.z).distance) >= 270, "Building over twice as far from highway")
			check(float(field.road_query(site.building.origin.x, site.building.origin.z).distance) <= 405, "Building within three times old distance")
			check(ExplorationSite.fits_strip(site.road, site.side, field.profile.terrain_half_width), "Complete site fits collision strip")
			for i in range(1, site.route.size()):
				var previous: Vector3 = site.route[i - 1]
				previous.y = field.height_at(previous.x, previous.z)
				for step in range(1, 11):
					var point: Vector3 = site.route[i - 1].lerp(site.route[i], step / 10.0)
					point.y = field.height_at(point.x, point.z)
					check(absf(point.x) < field.profile.terrain_half_width - 8, "Route inside collision terrain")
					var horizontal := Vector2(point.x - previous.x, point.z - previous.z).length()
					check(absf(point.y - previous.y) <= horizontal * tan(deg_to_rad(20)) + 0.01, "Walkable slope")
					check(field.surface(point.x, point.z).reserved, "Trail excludes random decoration")
					previous = point
			for x in [-10.0, 0.0, 10.0]:
				for z in [-10.0, 0.0, 10.0]:
					var p: Vector3 = site.building * Vector3(x, 0, z)
					check(absf(field.height_at(p.x, p.z) - p.y) < 0.15, "Building foundation")
	var main: Node3D = load("res://world/test_world.tscn").instantiate()
	var generator = main.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = WorldProfile.new()
	generator.profile.chunks_ahead = 1
	generator.profile.chunks_behind = 1
	root.add_child(main)
	current_scene = main
	generator.set_process(false)
	for monster in get_nodes_in_group(Groups.MONSTERS): monster.queue_free()
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if generator.active_chunks.all(func(chunk): return chunk.node.navigation_ready) and not generator.building: break
	for i in range(40): await physics_frame
	var site: Dictionary = generator.field.stop(0)
	check(ForestScenery.trees(generator.field, 0).size() > 1000, "Dense forest built in production band")
	# Spatial batching must neither lose trees nor shift them away from colliders.
	for entry in generator.active_chunks:
		var chunk: ChunkGenerator = entry.node
		var rendered: Array[Vector3] = []
		var rendered_count := 0
		for node in chunk.get_children():
			if not node is MultiMeshInstance3D or not str(node.name).begins_with("ForestTree"): continue
			for i in range(node.multimesh.instance_count):
				var pose: Transform3D = node.transform * node.multimesh.get_instance_transform(i)
				rendered.append(pose.origin)
				rendered_count += 1
		var planned := ForestScenery.trees(generator.field, chunk.band)
		check(rendered_count == planned.size(), "Forest cells retain every planned tree once")
		check(chunk.get_node("ForestTrunks").get_child_count() == planned.size(), "Tree collider count unchanged")
		# The dummy renderer returns identity from get_instance_transform().
		# GPU transform alignment is checked by the visible production playground.
		if DisplayServer.get_name() != "headless":
			var largest_error := 0.0
			for tree in planned:
				var nearest_error := INF
				for point in rendered: nearest_error = minf(nearest_error, point.distance_to(tree.point))
				largest_error = maxf(largest_error, nearest_error)
			check(largest_error < 0.001, "Rendered trunks remain within 1 mm of planned collision positions")
			print("FOREST ALIGN band=", chunk.band, " max_error_m=", largest_error)
	var space := main.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(site.frame.origin + Vector3.UP * 1.5, site.landmark)
	var hit := space.intersect_ray(ray)
	check(hit.is_empty() or hit.position.distance_to(site.landmark) < 15, "Visible landmark from parking")
	for i in [3, 5, 7, 9]:
		ray = PhysicsRayQueryParameters3D.create(site.route[i] + Vector3.UP * 1.5, site.frame.origin + Vector3.UP * 1.5)
		check(not space.intersect_ray(ray).is_empty(), "Route blocks view back to RV")
	var map := main.get_world_3d().navigation_map
	NavigationServer3D.map_force_update(map)
	var path := NavigationServer3D.map_get_path(map, site.route[0], site.route[-1], true)
	print("HORROR NAV points=", path.size(), " end=", path[-1] if not path.is_empty() else Vector3.ZERO, " target=", site.route[-1])
	check(not path.is_empty() and path[-1].distance_to(site.route[-1]) < 2, "Navigation reaches remote entrance through gaps")
	var next_road: Vector3 = generator.field.road_frame(220).origin
	path = NavigationServer3D.map_get_path(map, site.route[-1], next_road, true)
	check(not path.is_empty() and path[-1].distance_to(next_road) < 2, "Remote site navigation crosses a streaming boundary")
	var present := main.get_node("OutdoorPresentation") as OutdoorPresentation
	present.set_retro(true)
	check(present.effect.visible, "Outdoor retro enabled")
	main.get_node("PoiInstances").active_id = "test"
	present.apply()
	check(not present.effect.visible and main.get_viewport().scaling_3d_scale == 1, "Interior disables outdoor effect")
	main.get_node("PoiInstances").active_id = ""
	present.apply()
	check(present.effect.visible, "Return restores retro")
	present.set_retro(false)
	check(not present.effect.visible, "Native display available")
	var original_size := root.size
	root.size = Vector2i(1280, 800)
	await process_frame
	present.set_retro(true)
	var display_height := main.get_viewport().get_visible_rect().size.y
	check(is_equal_approx(main.get_viewport().scaling_3d_scale * display_height, minf(display_height, 540)), "Resize preserves target 3D height")
	check(present.effect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Filter leaves UI mouse input untouched")
	root.size = original_size
	check(not generator.protected_bands(site.route[4]).is_empty(), "Exploration pins site bands")
	var old_horizon: MeshInstance3D = generator.horizon
	await generator._spawn_band(-2, true)
	check(generator.horizon == old_horizon, "Pinned rear chunk does not move coarse horizon over explored terrain")
	# Build an actual streamed band with a remote site, including split walls.
	var remote: Dictionary = generator.field.stop(1)
	for band in generator.protected_bands(remote.route[4]):
		if not generator.active_chunks.any(func(c): return c.index == band): await generator._spawn_band(band, true)
	while not generator.active_chunks.all(func(chunk): return chunk.node.navigation_ready): await process_frame
	for i in range(10): await physics_frame
	NavigationServer3D.map_force_update(map)
	path = NavigationServer3D.map_get_path(map, remote.route[0], remote.route[-1], true)
	print("STREAM NAV site=", remote.s, " start=", remote.route[0], " end=", remote.route[-1], " points=", path.size())
	check(not path.is_empty() and path[-1].distance_to(remote.route[-1]) < 2, "Streamed remote site remains navigable")
	main.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: 100 horror worlds, routes, foundations, sightlines, navigation, display and streaming")
	quit(0 if failures.is_empty() else 1)
