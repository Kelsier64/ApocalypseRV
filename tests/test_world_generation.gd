extends SceneTree
const ROADSIDE_CACHE = preload("res://world/terrain/roadside_kit.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok and failures.size() < 25:
		failures.append(message)
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var legacy := WorldProfile.new()
	legacy.generation_version = 2
	var max_grade := 0.0
	var max_curvature := 0.0
	for seed_value in range(100):
		var field := WorldField.new(seed_value, legacy)
		var reverse := WorldField.new(seed_value, legacy)
		reverse.road_height(5100)
		for s in range(0, 5100, 5):
			var frame := field.road_frame(s)
			check(frame == reverse.road_frame(s), "Seed/load-order road replay")
			var grade := absf(field.road_height(s + 0.5) - field.road_height(s - 0.5))
			var dx := field.road_x(s + 0.5) - field.road_x(s - 0.5)
			var ddx := (field.road_x(s + 1) - 2.0 * field.road_x(s) + field.road_x(s - 1))
			var curvature := absf(ddx) / pow(1.0 + dx * dx, 1.5)
			max_grade = maxf(grade, max_grade)
			max_curvature = maxf(curvature, max_curvature)
			check(grade <= 0.0801, "Longitudinal grade <= 8 percent")
			check(curvature <= 1.0 / 80.0, "Turning radius >= 80m")
			check(field.road_width(s) >= 10 and field.road_width(s) <= 15, "Road width")
		for id in range(12):
			var site := field.stop(id)
			check(site == reverse.stop(id), "Site identity/load order")
			check(field.loot_plan(id) == reverse.loot_plan(id), "Loot replay")
			var loot := field.loot_plan(id)
			field.rng_for(id, "decoration").randf()
			check(loot == field.loot_plan(id), "Decorations do not perturb loot")
			if id > 1:
				var spacing: float = site.s - field.stop(id - 1).s
				check(spacing >= 300 and spacing <= 600, "Stop spacing")
			# Parking corners and building footprint must be supported and level.
			for x in [-6.0, 0.0, 6.0]:
				for z in [-12.0, 0.0, 12.0]:
					var point: Vector3 = site.frame * Vector3(x, 0, z)
					check(absf(field.height_at(point.x, point.z) - point.y) < 0.05, "Flat parking court")
			for x in [-4.5, 4.5]:
				for z in [-4.5, 4.5]:
					var point: Vector3 = site.building * Vector3(x, 0, z)
					check(absf(field.height_at(point.x, point.z) - point.y) < 0.05, "Building support")
			# Direct approach from road centre to court centre: no steep curb.
			var previous: Vector3 = site.road.origin
			for step in range(1, 34):
				var point: Vector3 = site.road * Vector3(float(site.side) * step, 0, 0)
				point.y = field.height_at(point.x, point.z)
				check(absf(point.y - previous.y) < 0.081, "Driveway grade")
				previous = point
	print("ROAD maxima grade=%.4f curvature=%.5f" % [max_grade, max_curvature])
	# Actual neighbouring mesh/collision and decoration contracts.
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var field := WorldField.new(42, legacy)
	var chunks: Array[ChunkGenerator] = []
	for index in [0, 1]:
		var chunk := ChunkGenerator.new()
		world.add_child(chunk)
		chunk.generate(field, index, POISpawner.new())
		chunks.append(chunk)
		for point in chunk.decoration_positions:
			check(not field.surface(point.x, point.z).reserved, "Decoration exclusion")
	var a: Array = chunks[0]._terrain.mesh.surface_get_arrays(0)
	var b: Array = chunks[1]._terrain.mesh.surface_get_arrays(0)
	for i in range(151):
		check(a[Mesh.ARRAY_VERTEX][50 * 151 + i] == b[Mesh.ARRAY_VERTEX][i], "Shared mesh edge")
		check(a[Mesh.ARRAY_NORMAL][50 * 151 + i].is_equal_approx(b[Mesh.ARRAY_NORMAL][i]), "Shared mesh normal")
	for i in range(90):
		await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 20, -150), Vector3(0, -20, -150))
	check(not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Seam has real collision")
	var map := world.get_world_3d().navigation_map
	var destination := field.road_frame(220).origin
	var path := NavigationServer3D.map_get_path(map, Vector3(0, 0, -45), destination, true)
	print("NAV boundary path: ", path.size(), " end=", path[path.size() - 1] if not path.is_empty() else Vector3.ZERO)
	check(not path.is_empty() and path[path.size() - 1].distance_to(destination) < 2.0, "Navigation crosses terrain band")
	var entrance: Vector3 = field.stop(0).building * Vector3(0, 0, 6.3)
	path = NavigationServer3D.map_get_path(map, Vector3(0, 0, -45), entrance, true)
	check(not path.is_empty() and path[path.size() - 1].distance_to(entrance) < 2.0, "Navigation reaches entrance approach")
	if failures.is_empty():
		print("PASS: 100 worlds, road limits, seed isolation, parking, approaches, mesh seams and collision")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	world.queue_free()
	await process_frame
	# Release local mesh arrays and generated resources before engine shutdown.
	_finish.call_deferred()

func _finish() -> void:
	# The test owns the process-wide roadside cache; release it before shutdown.
	ROADSIDE_CACHE.scenes.clear()
	ROADSIDE_CACHE.meshes.clear()
	ROADSIDE_CACHE.materials.clear()
	await physics_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
