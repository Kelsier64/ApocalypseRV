extends RefCounted
## v14 appearance, flora and mist checks, with frozen pre-v14 geometry fingerprints.
const CONTRACTS = preload("res://tests/support/terrain_contracts.gd")
const FROZEN := {
	6: [3807976057, 3370663327, 2309187816, 1401930638],
	12: [1682033219, 593278675, 573957769, 2789942250],
	13: [1572569537, 1002228210, 445820975, 2130005998],
}

class GeneratorStub extends Node:
	var world_seed := 42
	var profile: WorldProfile

class FogSettingsStub extends RefCounted:
	var enabled := false

	func volumetric_fog_enabled() -> bool:
		return enabled

static func run(tree: SceneTree, world: Node3D, check: Callable) -> void:
	_check_legacy_geometry(check)
	for seed_value: int in CONTRACTS.SEEDS:
		var field := WorldField.new(seed_value, CONTRACTS.profile(14))
		_check_frozen_road(field, check)
		_check_appearance(field, check)
		_check_local_screening(field, check)
		_check_mist_plans(field, check)
		await _check_forest_plans(field, world, check)
	_check_mist_clock(world, check)
	await _check_forest_rebuild(tree, world, check)

static func _check_mist_plans(field: WorldField, check: Callable) -> void:
	var bands: Array[int] = []
	for index in range(6):
		bands.append(floori((600.0 + (index + 0.45) * TerrainLandforms.REGION_LENGTH) / field.profile.chunk_length))
	for index in range(3):
		var owner := floori(float(field.landforms.river(index).s) / field.profile.chunk_length)
		for band in range(owner - 1, owner + 2):
			if band not in bands: bands.append(band)
	var reverse := WorldField.new(field.world_seed, CONTRACTS.profile(14))
	var reference: Dictionary = {}
	for index in range(bands.size() - 1, -1, -1):
		reference[bands[index]] = ForestFog.plans(reverse, bands[index])
	var deterministic := true
	var legal := true
	var clear_courts := true
	var anchored_rivers := true
	var ground_count := 0
	var river_count := 0
	for band: int in bands:
		var plans := ForestFog.plans(field, band)
		deterministic = deterministic and plans == reference[band]
		var ground_in_band := 0
		var rivers_in_band := 0
		var owners: Array[Dictionary] = []
		for river: Dictionary in field.landforms.rivers_near(-(band + 0.5) * field.profile.chunk_length):
			if floori(float(river.s) / field.profile.chunk_length) == band: owners.append(river)
		for plan: Dictionary in plans:
			if not plan.has_all(["position", "size", "river"]):
				legal = false
				continue
			var point: Vector3 = plan.position
			var size: Vector3 = plan.size
			legal = legal and point.is_finite() and size.is_finite() and size.x > 0.0 and size.y > 0.0 and size.z > 0.0
			var radius := Vector2(size.x, size.z).length() * 0.5
			for site: Dictionary in field.sites_near_z(point.z, radius + 400.0):
				clear_courts = clear_courts and field.court_distance(point.x, point.z, site) >= radius + 4.0 - 0.0001
			if not plan.river:
				ground_in_band += 1
				var sample := field.surface(point.x, point.z)
				legal = legal and not sample.reserved and not is_finite(float(sample.water_height))
				legal = legal and float(sample.road.distance) >= float(sample.road.width) * 0.5 + 12.0 - 0.0001
				continue
			rivers_in_band += 1
			var anchored := false
			for river: Dictionary in owners:
				for lateral: float in [-100.0, 0.0, 100.0]:
					var x := float(river.center_x) + lateral
					# Match the Vector3 precision used by generated world positions.
					var expected := Vector3(x, float(river.water_height) + 3.0, field.landforms.river_z(river, x))
					if point.x != expected.x or point.z != expected.z: continue
					anchored = point.y + size.y * 0.5 <= float(river.water_height) + 12.0 + 0.0001
			anchored_rivers = anchored_rivers and anchored
		legal = legal and ground_in_band <= 12 and rivers_in_band <= owners.size() * 3
		ground_count += ground_in_band
		river_count += rivers_in_band
	var label := "v14 seed %d: " % field.world_seed
	check.call(deterministic, label + "white-mist pockets are independent of chunk query order")
	check.call(legal and ground_count > 0 and river_count > 0, label + "bounded white-mist plans have positive finite volumes and dry ground anchors outside reserved roads")
	check.call(clear_courts, label + "every white-mist volume keeps its horizontal bounding circle at least 4m outside POI courts")
	check.call(anchored_rivers, label + "river mist belongs to its crossing band, follows the channel and stays below the bridge deck")

static func _check_mist_clock(world: Node3D, check: Callable) -> void:
	for version: int in [13, 14]:
		var host := Node3D.new()
		host.process_mode = Node.PROCESS_MODE_DISABLED
		world.add_child(host)
		var generator := GeneratorStub.new()
		generator.name = "WorldGenerator"
		generator.profile = CONTRACTS.profile(version)
		host.add_child(generator)
		var holder := WorldEnvironment.new()
		holder.name = "WorldEnvironment"
		holder.environment = Environment.new()
		host.add_child(holder)
		var sun := DirectionalLight3D.new()
		sun.name = "DirectionalLight3D"
		host.add_child(sun)
		var clock := WorldClock.new()
		clock.name = "WorldClock"
		clock.running = false
		clock.weather_running = false
		host.add_child(clock)
		check.call(clock.terrain_generation_version == version, "v%d mist clock reads its owning generator's profile" % version)
		# Inject only this clock's quality view; preserve the real autoload's preferences.
		var quality := FogSettingsStub.new()
		clock.game_settings = quality
		var material := ShaderMaterial.new()
		material.shader = load("res://world/terrain/white_mist.gdshader" if version == 14 else "res://world/terrain/forest_fog.gdshader") as Shader
		check.call(material.shader != null, "v%d local mist retains its own loadable shader" % version)
		for volumetric: bool in [false, true]:
			quality.enabled = volumetric
			for conditions: Vector3 in [Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 0.25), Vector3(0, 0, WorldWeather.FOG_LIGHT), Vector3(0, 0, WorldWeather.FOG_MEDIUM), Vector3(0, 0, WorldWeather.FOG_HEAVY)]:
				clock.weather.set_weather(conditions, true)
				clock.set_time(1, 12.0)
				var light := minf(conditions.z / WorldWeather.FOG_LIGHT, 1.0)
				var expected_density := 0.14 * (1.0 - conditions.x) * (1.0 - light)
				clock.register_fog(material)
				var registered := float(material.get_shader_parameter("density"))
				clock.apply_time()
				check.call(is_equal_approx(registered, expected_density) and is_equal_approx(float(material.get_shader_parameter("density")), expected_density), "v%d local mist registration and updates agree at weather %s / volumetric %s" % [version, conditions, volumetric])
				clock.unregister_fog(material)
				if conditions.z == 0.25: continue
				var begin := lerpf(24.0, 40.0, conditions.x) if version == 14 else lerpf(160.0 if volumetric else 18.0, 240.0, conditions.x)
				var end := lerpf(230.0, 290.0, conditions.x) if version == 14 else lerpf(420.0 if volumetric else 380.0, 700.0, conditions.x)
				if conditions.z > 0.0:
					begin = 8.0
					end = 220.0 if conditions.z == WorldWeather.FOG_LIGHT else (110.0 if conditions.z == WorldWeather.FOG_MEDIUM else 38.0)
				check.call(is_equal_approx(clock.environment.fog_depth_begin, begin) and is_equal_approx(clock.environment.fog_depth_end, end), "v%d depth mist keeps expected endpoints at weather %s / volumetric %s" % [version, conditions, volumetric])
				if version == 14: check.call(is_equal_approx(clock.environment.fog_depth_curve, 1.0), "v14 distance haze retains its curve at every quality/weather setting")
				var base_density := (0.0025 if version == 14 else 0.0015) * (1.0 - conditions.x) + conditions.y * 0.5 * 0.001
				check.call(is_equal_approx(clock.environment.volumetric_fog_density, base_density * (1.0 - light)), "v%d global volumetric-fog base fades fully when weather fog takes over" % version)
		if version == 14:
			clock.weather.set_weather(Vector3.ZERO, true)
			clock.set_time(1, 12.0)
			var noon := clock.environment.fog_light_color
			clock.set_time(1, 0.0)
			var night := clock.environment.fog_light_color
			check.call(noon.is_equal_approx(Color("c3cbc8")) and night.is_equal_approx(Color("030405")), "v14 gray-white daylight haze darkens with the native night lighting")
		host.free()

static func _check_legacy_geometry(check: Callable) -> void:
	for version: int in FROZEN:
		for seed_index in range(CONTRACTS.SEEDS.size()):
			var field := WorldField.new(CONTRACTS.SEEDS[seed_index], CONTRACTS.profile(version))
			var snapshot: Array = []
			for s: float in [0.0, 631.0, 1203.0, 2399.0, 4200.0, 6000.0, 7941.0, 10103.0, 12000.0]:
				snapshot.append([field.road_frame(s), field.road_width(s)])
				for x: float in [-1250.0, -450.0, -150.0, 0.0, 150.0, 450.0, 1250.0]:
					snapshot.append(field.surface(x, -s))
			if field.landforms != null:
				snapshot.append(field.landforms.rivers_near(-6000.0, 6000.0))
			check.call(snapshot.hash() == FROZEN[version][seed_index], "v%d seed %d: road/terrain/water fingerprint matches the pre-v14 baseline" % [version, field.world_seed])

static func _check_frozen_road(field: WorldField, check: Callable) -> void:
	var legacy := WorldField.new(field.world_seed, CONTRACTS.profile(13))
	var identical := true
	for index in range(int(CONTRACTS.LENGTH / CONTRACTS.STEP) + 1):
		var s := index * CONTRACTS.STEP
		identical = identical and field.road_frame(s) == legacy.road_frame(s)
		identical = identical and field.road_width(s) == legacy.road_width(s)
		if index % 12 != 0: continue
		for lateral: float in [-35.0, 0.0, 35.0]:
			var point := field.road_frame(s) * Vector3(lateral, 0.0, 0.0)
			identical = identical and field.road_query(point.x, point.z) == legacy.road_query(point.x, point.z)
	check.call(identical, "v14 seed %d: road frames, heights, widths and projections exactly equal v13 over 12km" % field.world_seed)

static func _appearance_weights(appearance: Vector3) -> PackedFloat64Array:
	var weights := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	weights[int(appearance.x)] += 1.0 - appearance.z
	weights[int(appearance.y)] += appearance.z
	return weights

static func _check_appearance(field: WorldField, check: Callable) -> void:
	var kinds: Dictionary = {}
	var blended := true
	var continuous := true
	var maximum_height_jump := 0.0
	for index in range(7):
		var end := 600.0 + (index + 1) * TerrainLandforms.REGION_LENGTH
		if end > CONTRACTS.LENGTH: break
		var middle := end - 180.0
		var appearance := field.landforms.appearance_at(middle)
		blended = blended and appearance.z > 0.0 and appearance.z < 1.0
		var expected: Color = TerrainLandforms.COLORS_V14[int(appearance.x)].lerp(TerrainLandforms.COLORS_V14[int(appearance.y)], appearance.z)
		blended = blended and field.landforms.color_at(middle).is_equal_approx(expected)
		for s: float in [end - 360.0, end]:
			var before := _appearance_weights(field.landforms.appearance_at(s - 0.01))
			var after := _appearance_weights(field.landforms.appearance_at(s + 0.01))
			for kind in range(6): continuous = continuous and absf(before[kind] - after[kind]) < 0.001
			for x: float in [-250.0, -80.0, 80.0, 250.0]:
				maximum_height_jump = maxf(maximum_height_jump, absf(field.height_at(x, -s - 0.01) - field.height_at(x, -s + 0.01)))
				var flora_before := field.landforms.flora_weights(x, -s + 0.01)
				var flora_after := field.landforms.flora_weights(x, -s - 0.01)
				continuous = continuous and flora_before.distance_to(flora_after) < 0.01
				var material_before := field.landforms.material_weights(field.landforms.appearance_at(s - 0.01))
				var material_after := field.landforms.material_weights(field.landforms.appearance_at(s + 0.01))
				continuous = continuous and material_before.distance_to(material_after) < 0.001
	for index in range(int(CONTRACTS.LENGTH / 30.0) + 1):
		var appearance := field.landforms.appearance_at(index * 30.0)
		kinds[int(appearance.x)] = true
		blended = blended and appearance.z >= 0.0 and appearance.z <= 1.0
		var sample := field.surface(250.0, -index * 30.0)
		var flora := field.landforms.flora_weights(250.0, -index * 30.0)
		blended = blended and sample.appearance == appearance and is_equal_approx(float(sample.moisture), flora.z)
		blended = blended and is_equal_approx(float(sample.moisture), field.landforms.material_weights(sample.appearance).y)
		blended = blended and flora.x >= 0.0 and flora.x <= 1.0 and flora.y >= 0.0 and flora.y <= 1.0 and flora.z >= 0.0 and flora.z <= 1.0
	check.call(kinds.size() == 6, "v14 seed %d: journey visits all six landforms" % field.world_seed)
	check.call(blended and continuous, "v14 seed %d: appearance/color interpolation is shared, bounded and continuous at every region boundary" % field.world_seed)
	check.call(maximum_height_jump < 0.2, "v14 seed %d: blended terrain remains continuous across landform transitions (%.4fm)" % [field.world_seed, maximum_height_jump])

static func _check_local_screening(field: WorldField, check: Callable) -> void:
	var fixtures: Dictionary = {}
	var screened: Dictionary = {}
	var heights: Dictionary = {}
	var maximum_road_error := 0.0
	var maximum_jump := 0.0
	for region in range(6):
		for candidate in range(9):
			var s := 600.0 + (region + 0.15 + candidate * 0.075) * TerrainLandforms.REGION_LENGTH
			var kind := field.landforms.kind_at(s)
			if kind not in ["meadow", "wetland", "ridge", "basin"]: continue
			if not field.landforms.crossing_clearance(s, 190.0): continue
			var frame := field.road_frame(s)
			var sites := field.sites_near_z(frame.origin.z)
			var clear := true
			for site: Dictionary in sites:
				clear = clear and field.court_distance(frame.origin.x, frame.origin.z, site) > 24.0
			if not clear: continue
			var half_width := field.road_width(s) * 0.5
			# A dry viaduct still supplies a road-height observation point.
			# Only grounded road terrain must match the carriageway; the
			# existing physical support suite checks suspended bridge decks.
			if field.landforms.bridge_gap(s) == 0.0:
				for lateral: float in [-half_width + 0.2, 0.0, half_width - 0.2]:
					var point := frame * Vector3(lateral, 0.0, 0.0)
					maximum_road_error = maxf(maximum_road_error, absf(field.height_at(point.x, point.z) - frame.origin.y))
			var valid := false
			var blocked := false
			for side: float in [-1.0, 1.0]:
				for beyond_edge: float in [20.0, 30.0, 40.0, 50.0, 60.0]:
					var point := frame * Vector3(side * (half_width + beyond_edge), 0.0, 0.0)
					var sample := field.surface(point.x, point.z)
					if sample.reserved or is_finite(float(sample.water_height)): continue
					var outside_courts := true
					for site: Dictionary in sites:
						outside_courts = outside_courts and field.court_distance(point.x, point.z, site) > 16.0
					if not outside_courts: continue
					valid = true
					# A local terrain intersection with a horizontal eye-height
					# ray, independent of fog or foliage. Open intervals are allowed.
					blocked = blocked or float(sample.height) > frame.origin.y + 1.65
					heights[Vector2(point.x, point.z)] = float(sample.height)
				# Small world-space probes on both axes catch local steps at
				# the bank's onset, crest and fade.
				for beyond_edge: float in [7.0, 21.0, 43.0, 82.0]:
					var point := frame * Vector3(side * (half_width + beyond_edge), 0.0, 0.0)
					for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
						var before := point - axis * 0.01
						var after := point + axis * 0.01
						maximum_jump = maxf(maximum_jump, absf(field.height_at(before.x, before.z) - field.height_at(after.x, after.z)))
			if valid: fixtures[kind] = int(fixtures.get(kind, 0)) + 1
			if blocked: screened[kind] = int(screened.get(kind, 0)) + 1
	var label := "v14 seed %d: " % field.world_seed
	for kind: String in ["meadow", "wetland", "ridge", "basin"]:
		check.call(int(fixtures.get(kind, 0)) >= 2 and int(screened.get(kind, 0)) >= 2, label + "%s has several dry local roadside fixtures screening a 1.65m eye line (%d/%d)" % [kind, int(screened.get(kind, 0)), int(fixtures.get(kind, 0))])
	check.call(maximum_road_error < 0.12, label + "nearby screening terrain leaves the full dry carriageway level (%.4fm)" % maximum_road_error)
	check.call(maximum_jump < 0.2, label + "roadside banks remain locally continuous on both horizontal axes (%.4fm)" % maximum_jump)
	var reverse := WorldField.new(field.world_seed, CONTRACTS.profile(14))
	var points := heights.keys()
	points.reverse()
	for point: Vector2 in points: reverse.height_at(point.x, point.y)
	var deterministic := not points.is_empty()
	for point: Vector2 in heights:
		deterministic = deterministic and reverse.height_at(point.x, point.y) == heights[point]
	check.call(deterministic, label + "local screening heights are independent of query order")

static func _check_forest_plans(field: WorldField, world: Node3D, check: Callable) -> void:
	var chunk := ChunkGenerator.new()
	chunk.field = field
	world.add_child(chunk)
	var reverse := WorldField.new(field.world_seed, CONTRACTS.profile(14))
	var other := ChunkGenerator.new()
	other.field = reverse
	world.add_child(other)
	var bands: Array[int] = []
	for index in range(6): bands.append(floori((600.0 + (index + 0.45) * TerrainLandforms.REGION_LENGTH) / field.profile.chunk_length))
	for index in range(bands.size() - 1, -1, -1): await ForestScenery.prepare(other, bands[index], false)
	var accepted := 0
	var legal := true
	var deterministic := true
	var broadleaf := 0
	for band: int in bands:
		await ForestScenery.prepare(chunk, band, false)
		var planned := ForestScenery.trees(field, band)
		deterministic = deterministic and planned == ForestScenery.trees(reverse, band)
		for entry: Dictionary in planned:
			var point: Vector3 = entry.point
			var sample := field.surface(point.x, point.z)
			var normal: Vector3 = entry.normal
			legal = legal and normal.y >= cos(deg_to_rad(40.0)) - 0.00001
			if accepted % 16 == 0: legal = legal and field.normal_at(point.x, point.z).y >= cos(deg_to_rad(40.0)) - 0.00001
			legal = legal and not sample.reserved and not is_finite(float(sample.water_height))
			legal = legal and float(sample.road.distance) >= float(sample.road.width) * 0.5 + 5.0
			legal = legal and int(entry.mesh_kind) >= 0 and int(entry.mesh_kind) < 8
			for site: Dictionary in field.sites_near_z(point.z): legal = legal and field.court_distance(point.x, point.z, site) >= 4.0
			if int(entry.mesh_kind) >= 6: broadleaf += 1
			accepted += 1
	check.call(accepted > 0 and broadleaf > 0, "v14 seed %d: six landform forest samples contain trees and broadleaf variants" % field.world_seed)
	check.call(legal, "v14 seed %d: accepted trees avoid slopes above 40 degrees, water, road shoulders and POI courts" % field.world_seed)
	check.call(deterministic, "v14 seed %d: forest layout and art variants are independent of preparation order" % field.world_seed)
	chunk.queue_free()
	other.queue_free()

static func _forest_snapshot(chunk: ChunkGenerator) -> Dictionary:
	var result: Dictionary = {}
	var body := chunk.get_node("ForestTrunks") as ForestTrunks
	for shape: CollisionShape3D in body.get_children():
		var point: Vector3 = shape.get_meta("tree_point")
		var visual: Dictionary = body.visuals[point]
		result[shape.get_meta("tree_id")] = {"collision": shape.transform, "pose": visual.node.transform * visual.pose, "mesh": visual.node.multimesh.mesh}
	return result

static func _ground_snapshot(chunk: ChunkGenerator, check: Callable) -> Dictionary:
	var result: Dictionary = {}
	var legal := true
	var headless := DisplayServer.get_name() == "headless"
	for node: MultiMeshInstance3D in chunk.find_children("ForestBrush*", "MultiMeshInstance3D", false, false):
		var kind: int = node.get_meta("forest_kind")
		legal = legal and node.multimesh.mesh == FloraMeshes.ground(kind)
		legal = legal and node.find_children("*", "CollisionShape3D", true, false).is_empty()
		if headless:
			# Dummy RenderingServer cannot read back instance transforms. Compare
			# CPU batch metadata here; native renderer checks every pose below.
			result[str(node.name)] = {"cell": node.transform, "mesh": node.multimesh.mesh, "kind": kind, "count": node.multimesh.instance_count}
			continue
		for index in range(node.multimesh.instance_count):
			var pose := node.transform * node.multimesh.get_instance_transform(index)
			var point := pose.origin
			var sample := chunk.field.surface(point.x, point.z)
			legal = legal and not sample.reserved and not is_finite(float(sample.water_height))
			legal = legal and float(sample.road.distance) >= float(sample.road.width) * 0.5 + 4.5
			result[point] = {"pose": pose, "kind": kind}
	var message := "v14 ground-cover batch checks retain real mesh, kind, cell, count and no colliders" if headless else "v14 generated ground cover uses real grass/reed/scree/shrub meshes outside water, roads and reserved POIs"
	check.call(not result.is_empty() and legal, message)
	return result

static func _check_forest_rebuild(tree: SceneTree, world: Node3D, check: Callable) -> void:
	var field := WorldField.new(42, CONTRACTS.profile(14))
	var band := -1
	var chunk := ChunkGenerator.new()
	chunk.field = field
	world.add_child(chunk)
	# Choose a real broadleaf habitat, irrespective of the seed's biome order.
	for index in range(6):
		var candidate := floori((600.0 + (index + 0.45) * TerrainLandforms.REGION_LENGTH) / field.profile.chunk_length)
		await ForestScenery.prepare(chunk, candidate, false)
		for entry: Dictionary in ForestScenery.trees(field, candidate):
			if int(entry.mesh_kind) >= 6:
				band = candidate
				break
		if band >= 0: break
	check.call(band >= 0, "v14 rebuild fixture locates an actual broadleaf habitat")
	if band < 0:
		chunk.queue_free()
		return
	chunk.band = band
	await ForestScenery.build(chunk, false)
	var planned := ForestScenery.trees(field, band)
	var reference := _forest_snapshot(chunk)
	var ground_reference := _ground_snapshot(chunk, check)
	var body := chunk.get_node("ForestTrunks") as ForestTrunks
	var broadleaf := 0
	var active := body.collision_layer == 1 and body.is_inside_tree()
	for index in range(planned.size()):
		var key := TreeImpact.forest_id(band, index)
		active = active and reference.has(key)
		if int(planned[index].mesh_kind) >= 6 and reference.has(key):
			broadleaf += 1
			active = active and reference[key].mesh == ForestMeshes.tree(planned[index].mesh_kind)
	for shape: CollisionShape3D in body.get_children(): active = active and not shape.disabled and shape.shape is BoxShape3D
	check.call(active and broadleaf > 0, "v14 broadleaf instances have their real mesh, stable tree ID and active physical trunk")
	for kind: int in [6, 7]:
		var mesh := ForestMeshes.tree(kind)
		check.call(mesh.get_surface_count() >= 2 and mesh.get_faces() != ForestMeshes.tree(0).get_faces(), "v14 broadleaf %d contains distinct trunk and foliage geometry" % kind)
		if mesh.get_surface_count() >= 2:
			check.call(not TreeFall._is_foliage(mesh.surface_get_material(0)) and TreeFall._is_foliage(mesh.surface_get_material(1)), "v14 broadleaf %d retains TreeFall's wood/foliage material classification" % kind)
	for kind in range(5):
		var mesh := FloraMeshes.ground(kind)
		check.call(mesh.get_faces().size() >= 12 and mesh.get_aabb().size.y > 0.05, "v14 ground-cover kind %d contains real three-dimensional geometry" % kind)
	check.call(not planned.is_empty(), "v14 rebuild fixture contains a destructible tree")
	if planned.is_empty():
		chunk.queue_free()
		return
	var removed := TreeImpact.forest_id(band, floori(planned.size() / 2.0))
	field.destroyed_trees[removed] = true
	chunk.queue_free()
	await tree.process_frame
	var rebuilt := ChunkGenerator.new()
	rebuilt.field = WorldField.new(42, CONTRACTS.profile(14))
	rebuilt.field.destroyed_trees = field.destroyed_trees.duplicate()
	rebuilt.band = band
	world.add_child(rebuilt)
	await ForestScenery.build(rebuilt, true)
	var after := _forest_snapshot(rebuilt)
	var ground_message := "v14 sliced rebuilding preserves ground-cover batch mesh, kind, cell and count" if DisplayServer.get_name() == "headless" else "v14 sliced rebuilding preserves every ground-cover kind and transform"
	check.call(_ground_snapshot(rebuilt, check) == ground_reference, ground_message)
	check.call(not after.has(removed), "v14 saved tombstone removes the same tree during sliced forest rebuilding")
	reference.erase(removed)
	check.call(after == reference, "v14 sliced forest rebuilding preserves every surviving mesh, pose, trunk and stable identity")
	check.call(ForestScenery.trees(rebuilt.field, band) == planned, "v14 tombstones do not renumber or reroll the planned tree array")
	rebuilt.queue_free()
	await tree.process_frame
