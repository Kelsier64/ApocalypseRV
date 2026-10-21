extends RefCounted
## Current terrain appearance, flora, mist and deterministic geometry checks.
const CONTRACTS = preload("res://tests/support/terrain_contracts.gd")
const WORLD_GENERATOR = preload("res://world/world_generator.gd")
const ATMOSPHERE = preload("res://world/world_atmosphere_profile.tres")
const ATMOSPHERE_CONTRACTS = preload("res://tests/support/atmosphere_contracts.gd")
const FROZEN := [2173645473, 2698986667, 2622734014, 1237357782]
const ROAD_FROZEN := [2290317034, 3962838430, 934878813, 16663958]

class GeneratorStub extends Node:
	var world_seed := 42
	var profile: WorldProfile

class SceneryGeneratorStub extends GeneratorStub:
	var clearance := 80.0
	var last_eye := Vector3.ZERO
	var samples := 0

	func completed_scenery_clearance(eye: Vector3) -> float:
		last_eye = eye
		samples += 1
		return clearance

class FogSettingsStub extends RefCounted:
	var enabled := false

	func volumetric_fog_enabled() -> bool:
		return enabled

static func run(tree: SceneTree, world: Node3D, check: Callable) -> void:
	_check_geometry(check)
	for seed_value: int in CONTRACTS.SEEDS:
		var field := WorldField.new(seed_value, CONTRACTS.profile(14))
		_check_frozen_road(field, check)
		_check_appearance(field, check)
		_check_grounded_corridor(field, check)
		_check_local_screening(field, check)
		_check_mist_plans(field, check)
		await _check_forest_plans(field, world, check)
	_check_mist_clock(world, check)
	_check_streaming_mist_clock(world, check)
	_check_forest_culling(world, check)
	_check_completed_scenery(check)
	ATMOSPHERE_CONTRACTS.run(world, check)
	await _check_forest_rebuild(tree, world, check)

static func _check_grounded_corridor(field: WorldField, check: Callable) -> void:
	var dry_samples := 0
	var elevated_samples := 0
	var shoulder_samples := [0, 0, 0]
	var near_level_samples := [0, 0, 0]
	var distances := [4.0, 10.0, 20.0]
	for s in range(600, int(CONTRACTS.LENGTH) + 1, 15):
		if not field.landforms.crossing_clearance(float(s), 200.0): continue
		dry_samples += 1
		if field.landforms.bridge_at(float(s)):
			elevated_samples += 1
			continue
		var frame := field.road_frame(float(s))
		var half_width := field.road_width(float(s)) * 0.5
		for side: float in [-1.0, 1.0]:
			for index in range(distances.size()):
				var beyond_edge: float = distances[index]
				var point := frame * Vector3(side * (half_width + beyond_edge), 0.0, 0.0)
				var sample := field.surface(point.x, point.z)
				if sample.reserved or float(sample.gravel) > 0.2 or is_finite(float(sample.water_height)): continue
				shoulder_samples[index] += 1
				if absf(float(sample.height) - frame.origin.y) <= 3.0: near_level_samples[index] += 1
	var label := "v14 seed %d: " % field.world_seed
	var elevated_fraction := float(elevated_samples) / maxi(dry_samples, 1)
	check.call(dry_samples > 0 and elevated_fraction > 0.0 and elevated_fraction <= 0.12, label + "dry viaducts remain occasional across 12km (%.1f%%)" % (elevated_fraction * 100.0))
	for index in range(distances.size()):
		var near_level_fraction := float(near_level_samples[index]) / maxi(shoulder_samples[index], 1)
		check.call(shoulder_samples[index] > 0 and near_level_fraction >= 0.95, label + "at least 95%% of natural terrain %.0fm beyond grounded road edges stays within 3m of the road (%.1f%%)" % [distances[index], near_level_fraction * 100.0])

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
	for version: int in [14]:
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
		var sky_path := "res://world/terrain/overcast_v14.gdshader"
		check.call(clock.sky_material.shader == load(sky_path) and clock.sky_material.shader.code.contains("render_mode disable_fog;") == false, "v%d sky integrates native distance and volumetric fog" % version)
		check.call(is_equal_approx(clock.environment.fog_sky_affect, 1.0) and is_equal_approx(clock.environment.volumetric_fog_sky_affect, 1.0), "v%d sky receives the expected distance and volumetric fog integration" % version)
		# Inject only this clock's quality view; preserve the real autoload's preferences.
		var quality := FogSettingsStub.new()
		clock.game_settings = quality
		var material := ShaderMaterial.new()
		material.shader = load("res://world/terrain/white_mist.gdshader") as Shader
		check.call(material.shader != null, "v%d local mist retains its own loadable shader" % version)
		for volumetric: bool in [false, true]:
			quality.enabled = volumetric
			for conditions: Vector3 in [Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 0.25), Vector3(0.5, 1, 0.25), Vector3(0, 0, WorldWeather.FOG_LIGHT), Vector3(0, 0, WorldWeather.FOG_MEDIUM), Vector3(0, 0, WorldWeather.FOG_HEAVY)]:
				clock.weather.set_weather(conditions, true)
				clock.set_time(1, 12.0)
				# Fixed observable tier values, independent of the atmosphere implementation.
				var densities := {Vector3.ZERO: [0.14, 0.0025], Vector3(1, 0, 0): [0.0, 0.0], Vector3(0, 2, 0): [0.14, 0.0035], Vector3(0, 0, 0.25): [0.07, 0.00125], Vector3(0.5, 1, 0.25): [0.035, 0.00075], Vector3(0, 0, 0.5): [0.0, 0.0], Vector3(0, 0, 1): [0.0, 0.0], Vector3(0, 0, 2): [0.0, 0.0]}
				var expected_density: float = densities[conditions][0]
				var expected_global: float = densities[conditions][1]
				var expected_white := 1.0
				check.call(is_equal_approx(float(ATMOSPHERE.mist(conditions).white_strength), expected_white), "v14 permanent white mist persists through clear skies, rain and every weather fog tier at %s" % conditions)
				var horizon: Color = clock.sky_material.get_shader_parameter("horizon_color")
				check.call(clock.environment.fog_light_color.is_equal_approx(horizon), "v14 fog and sky share the terminal color so distant objects cannot reappear as pale cutouts")
				check.call(clock.environment.volumetric_fog_enabled == (volumetric and expected_global > 0.0), "v14 zero-density weather skips volumetric scattering and low mist restores it without changing distance fog quality")
				clock.register_fog(material)
				var registered := float(material.get_shader_parameter("density"))
				clock.apply_time()
				check.call(is_equal_approx(registered, expected_density) and is_equal_approx(float(material.get_shader_parameter("density")), expected_density), "v%d local mist registration and updates agree at weather %s / volumetric %s" % [version, conditions, volumetric])
				clock.unregister_fog(material)
				var endpoints := {0.0: [24.0, 230.0, 69.0], 0.25: [16.0, 190.0, 57.0], 0.5: [8.0, 150.0, 45.0], 1.0: [8.0, 110.0, 33.0], 2.0: [8.0, 38.0, 11.4]}
				var begin: float = endpoints[conditions.z][0]
				if conditions == Vector3(1, 0, 0): begin = 64.0
				if conditions == Vector3(0.5, 1, 0.25): begin = 26.0
				var end: float = endpoints[conditions.z][1]
				var curve := 1.0
				check.call(is_equal_approx(clock.environment.volumetric_fog_length, endpoints[conditions.z][2]), "v14 scattering integrates before opaque distance haze at weather %s / volumetric %s" % [conditions, volumetric])
				check.call(is_equal_approx(clock.environment.fog_depth_begin, begin) and is_equal_approx(clock.environment.fog_depth_end, end), "v%d depth mist keeps expected endpoints at weather %s / volumetric %s" % [version, conditions, volumetric])
				check.call(is_equal_approx(clock.environment.fog_depth_curve, curve), "v%d distance haze retains its expected curve at every quality/weather setting" % version)
				check.call(is_equal_approx(clock.environment.volumetric_fog_density, expected_global), "v%d global volumetric fog follows its weather contract" % version)
			_check_mist_transition(clock, material, volumetric, check)
			_check_weather_appearance(clock, check)
		clock.weather.set_weather(Vector3(0, 0, WorldWeather.FOG_HEAVY), true)
		clock.set_time(1, 12.0)
		var noon := clock.environment.fog_light_color
		clock.set_time(1, 0.0)
		var night := clock.environment.fog_light_color
		check.call(noon.is_equal_approx(Color("c3cbc8")) and night.is_equal_approx(Color("030405")), "v14 gray-white daylight haze darkens with the native night lighting")
		host.free()

static func _check_weather_appearance(clock: WorldClock, check: Callable) -> void:
	for fixture: Array in [[Vector3(1, 0, 0), Color("d0cbb8"), 1.3], [Vector3.ZERO, Color("a4afb0"), 0.45], [Vector3(0, 0, 0.5), Color("c3cbc8"), 0.354375]]:
		clock.weather.set_weather(fixture[0], true)
		clock.set_time(1, 12.0)
		check.call(clock.environment.fog_light_color.is_equal_approx(fixture[1]) and is_equal_approx(clock.sun.light_energy, fixture[2]), "v14 sunny, overcast and light fog have distinct daytime terminal tones and sun strengths at %s" % fixture[0])
		var saved := clock.weather.capture()
		clock.set_deviation_fog(WorldWeather.FOG_LIGHT)
		check.call(clock.environment.fog_light_color.is_equal_approx(Color("c3cbc8")) and is_equal_approx(clock.environment.fog_depth_end, 150.0) and clock.weather.capture() == saved, "v14 deviation light fog uses the same white haze and cap without changing natural weather or RNG")
		clock.set_deviation_fog(0.0)
		check.call(clock.environment.fog_light_color.is_equal_approx(fixture[1]) and is_equal_approx(clock.sun.light_energy, fixture[2]) and clock.weather.capture() == saved, "v14 clearing deviation restores the natural weather's terminal tone and sun strength")
	clock.weather.set_weather(Vector3(1, 0, 0), true)
	clock.weather.set_weather(Vector3.ZERO)
	clock.weather.advance(WorldWeather.TRANSITION * 0.5)
	var saved := clock.weather.capture()
	clock.apply_time()
	check.call(is_equal_approx(clock.environment.fog_depth_begin, 44.0) and is_equal_approx(clock.environment.fog_depth_end, 230.0) and clock.environment.fog_light_color.is_equal_approx(Color("a4afb0").lerp(Color("d0cbb8"), 0.5)) and is_equal_approx(clock.sun.light_energy, 0.875) and clock.weather.capture() == saved, "v14 a natural clear-to-overcast midpoint blends onset, terminal tone and sun energy without a render-time RNG draw")

static func _check_mist_transition(clock: WorldClock, material: ShaderMaterial, _volumetric: bool, check: Callable) -> void:
	for fixture: Array in [[0.625, 140.0], [0.75, 130.0], [1.5, 74.0]]:
		var profile := ATMOSPHERE.mist(Vector3(0, 0, fixture[0]))
		check.call(is_equal_approx(float(profile.depth_end), fixture[1]) and is_equal_approx(float(profile.white_strength), 1.0) and is_zero_approx(float(profile.global_density)) and is_zero_approx(float(profile.local_density)), "v14 distance haze strengthens while scattering volumes remain absent above light fog at strength %.3f" % fixture[0])
	clock.set_deviation_fog(0.0)
	clock.weather.set_weather(Vector3.ZERO, true)
	clock.weather.set_weather(Vector3(0, 0, WorldWeather.FOG_LIGHT))
	clock.weather.advance(WorldWeather.TRANSITION * 0.5)
	clock.apply_time()
	clock.register_fog(material)
	var midpoint_end := 190.0
	check.call(clock.weather.sample().is_equal_approx(Vector3(0, 0, 0.25)) and clock.weather.target.z == WorldWeather.FOG_LIGHT, "v14 natural fog transition retains its source/target and produces the halfway sample")
	check.call(clock.environment.fog_light_color.is_equal_approx(Color("a4afb0").lerp(Color("c3cbc8"), 0.5)), "v14 natural light-fog midpoint blends the overcast and white terminal tones")
	check.call(is_equal_approx(clock.environment.fog_depth_end, midpoint_end) and is_equal_approx(clock.environment.volumetric_fog_density, 0.00125) and is_equal_approx(float(material.get_shader_parameter("density")), 0.07), "v14 global and newly registered local mist use the interpolated weather sample")
	var saved := clock.weather.capture()
	var restored := WorldWeather.new()
	check.call(restored.restore(saved) and restored.capture() == saved and restored.sample() == clock.weather.sample(), "v14 weather round trip preserves transition source, target, progress, duration and RNG state")
	clock.weather = restored
	clock.apply_time()
	check.call(is_equal_approx(clock.environment.fog_depth_end, midpoint_end) and is_equal_approx(float(material.get_shader_parameter("density")), 0.07), "v14 restored weather reproduces the same global and local mist")
	clock.set_deviation_fog(WorldWeather.FOG_MEDIUM)
	check.call(clock.effective_visual_weather().z == WorldWeather.FOG_MEDIUM and is_equal_approx(clock.environment.fog_depth_end, 110.0) and is_zero_approx(clock.environment.volumetric_fog_density) and is_zero_approx(float(material.get_shader_parameter("density"))), "v14 deviation fog strengthens distance haze and suppresses scattering volumes at medium fog")
	check.call(clock.weather.capture() == saved, "v14 visual deviation fog preserves natural weather transition and RNG")
	clock.set_deviation_fog(0.0)
	check.call(is_equal_approx(clock.environment.fog_depth_end, midpoint_end) and is_equal_approx(float(material.get_shader_parameter("density")), 0.07), "v14 clearing deviation fog resumes the unchanged natural weather blend")
	clock.unregister_fog(material)

static func _check_forest_culling(world: Node3D, check: Callable) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8, 20, 6)
	# Two widely separated, scaled and rotated instances exercise the whole
	# cell's nearest geometry rather than a single plant's origin or mesh size.
	var poses: Array = [Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(1.5, 1, 0.8)), Vector3(1, 0, 1)), Transform3D(Basis(Vector3.UP, -0.4).scaled(Vector3(0.9, 1.8, 1.2)), Vector3(47, 8, 47))]
	var bounds: AABB = poses[0] * mesh.get_aabb()
	for index in range(1, poses.size()): bounds = bounds.merge(poses[index] * mesh.get_aabb())
	var radius := bounds.size.length() * 0.5
	for version: int in [14]:
		var chunk := ChunkGenerator.new()
		chunk.field = WorldField.new(42, CONTRACTS.profile(version))
		world.add_child(chunk)
		for title: String in ["ForestBrush0", "ForestTree0"]:
			var instances := ForestScenery.batch(chunk, title, mesh, poses)
			var node: MultiMeshInstance3D = instances[poses[0].origin].node
			var base_end := 160.0 if title.begins_with("ForestBrush") else 340.0
			check.call(instances.size() == 2 and instances[poses[1].origin].node == node and is_equal_approx(node.visibility_range_end_margin, 16.0), "v%d %s fixture shares one bounded cell with 16m hysteresis" % [version, title])
			check.call(node.multimesh.custom_aabb.size.is_equal_approx(bounds.size), "v14 %s explicit batch AABB contains every scaled and rotated source mesh, including headless" % title)
			check.call(node.visibility_range_end >= base_end and node.visibility_range_end - node.visibility_range_end_margin - radius >= 238.0 - 0.0001, "v14 %s nearest geometry stays beyond 230m terminal fog and 8m buffer through both culling directions" % title)
			if DisplayServer.get_name() != "headless":
				check.call(node.multimesh.get_aabb().size.is_equal_approx(bounds.size), "v14 %s renderer uses the complete explicit batch bounds" % title)
		chunk.free()

static func _check_streaming_mist_clock(world: Node3D, check: Callable) -> void:
	var previous := world.get_viewport().get_camera_3d()
	for version: int in [14]:
		var host := Node3D.new()
		host.position = Vector3(50, 30, -100)
		host.process_mode = Node.PROCESS_MODE_DISABLED
		world.add_child(host)
		var generator := SceneryGeneratorStub.new()
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
		var camera := Camera3D.new()
		camera.position = Vector3(2, 4, -5)
		host.add_child(camera)
		camera.make_current()
		var clock := WorldClock.new()
		clock.running = false
		clock.weather_running = false
		host.add_child(clock)
		clock.game_settings = FogSettingsStub.new()
		clock.weather.set_weather(Vector3.ZERO, true)
		clock.set_time(1, 12.0)
		var saved := clock.weather.capture()
		check.call(generator.last_eye.is_equal_approx(camera.global_position) and is_equal_approx(clock.environment.fog_depth_end, 72.0), "v14 streaming guard samples the actual viewport camera and hides incomplete scenery with an 8m buffer")
		camera.position += Vector3(9, 0, -12)
		generator.clearance = 40.0
		clock.apply_time()
		check.call(generator.last_eye.is_equal_approx(camera.global_position) and is_equal_approx(clock.environment.fog_depth_end, 32.0) and is_equal_approx(clock.environment.fog_depth_begin, 16.0), "v14 camera offsets immediately tighten both fog endpoints before missing scenery is exposed")
		check.call(is_equal_approx(clock.environment.volumetric_fog_length, 9.6), "v14 near streaming guard shortens scattering integration ahead of the opaque haze")
		generator.clearance = 400.0
		clock.apply_time()
		check.call(is_equal_approx(clock.environment.fog_depth_end, 32.0), "v14 a zero-delta weather or settings refresh cannot reveal a completed band abruptly")
		clock.apply_time(0.5)
		check.call(is_equal_approx(clock.environment.fog_depth_end, 42.0), "v14 completed scenery opens at only 20m per real second")
		clock.advance(0.5)
		check.call(is_equal_approx(clock.environment.fog_depth_end, 52.0) and clock.weather.capture() == saved, "v14 clock advancement passes real frame time to scenery recovery without changing paused natural weather or RNG")
		check.call(is_equal_approx(clock.environment.volumetric_fog_length, 15.6), "v14 scattering integration follows gradual distance fog recovery")
		clock.weather.set_weather(Vector3(0, 0, WorldWeather.FOG_HEAVY), true)
		clock.apply_time(50.0)
		check.call(is_equal_approx(clock.environment.fog_depth_end, 38.0), "v14 completed coverage never weakens the heavy weather fog cap")
		clock.weather.set_weather(Vector3(1, 0, 0), true)
		clock.apply_time()
		check.call(is_equal_approx(clock.environment.fog_depth_end, 230.0), "v14 fully recovered clear skies retain the permanent 230m fog cap")
		generator.clearance = 40.0
		clock.apply_time()
		check.call(is_equal_approx(clock.environment.fog_depth_end, 32.0) and is_equal_approx(clock.environment.fog_depth_begin, 16.0), "v14 the later sunny onset tightens to half the terminal distance as soon as completed coverage contracts")
		generator.clearance = 6.0
		clock.apply_time()
		check.call(is_equal_approx(clock.environment.fog_depth_end, 1.0) and is_equal_approx(clock.environment.fog_depth_begin, 0.5), "v14 an uncovered eye clamps the guard to a positive, ordered near fog interval")
		check.call(is_equal_approx(clock.environment.volumetric_fog_length, 0.3), "v14 minimum streaming clearance retains a positive scattering integration length")
		camera.clear_current()
		host.free()
	if is_instance_valid(previous): previous.make_current()

static func _check_completed_scenery(check: Callable) -> void:
	# Off-tree construction prevents generation or navigation side effects;
	# active_chunks is the real generator's completed-publication contract.
	var generator := WORLD_GENERATOR.new()
	generator.profile = CONTRACTS.profile(14)
	check.call(is_zero_approx(generator.completed_scenery_clearance(Vector3(0, 0, -75))), "v14 empty completed scenery has no safe viewing clearance")
	generator.active_chunks = [{"index": 1}, {"index": -1}, {"index": 0}]
	check.call(is_equal_approx(generator.completed_scenery_clearance(Vector3(0, 0, -75)), 225.0) and is_equal_approx(generator.completed_scenery_clearance(Vector3(0, 0, -149)), 151.0), "v14 completed clearance measures the nearest edge of contiguous bands independently of entry order")
	generator.active_chunks.append({"index": -3})
	generator.active_chunks.append({"index": 3})
	check.call(is_equal_approx(generator.completed_scenery_clearance(Vector3(0, 0, -75)), 225.0), "v14 disconnected pinned islands cannot extend safe scenery clearance across missing bands")
	generator.active_chunks = [{"index": -1}, {"index": 0}, {"index": 2}, {"index": 3}]
	check.call(is_equal_approx(generator.completed_scenery_clearance(Vector3(0, 0, -75)), 75.0) and is_zero_approx(generator.completed_scenery_clearance(Vector3(0, 0, -225))), "v14 an unfinished or removed band shortens coverage immediately and gives no clearance inside the gap")
	check.call(is_equal_approx(generator.completed_scenery_clearance(Vector3(0, 0, 75)), 75.0) and is_equal_approx(generator.completed_scenery_clearance(Vector3(0, 0, -375)), 75.0), "v14 completed clearance supports negative bands and separate completed islands")
	check.call(is_zero_approx(generator.completed_scenery_clearance(Vector3(0, 0, 150))) and is_zero_approx(generator.completed_scenery_clearance(Vector3(0, 0, -150))), "v14 exact completed edges have zero clearance when the adjoining band is missing")
	generator.profile.chunk_length = 100.0
	generator.active_chunks = [{"index": -1}, {"index": 0}, {"index": 1}]
	check.call(is_equal_approx(generator.completed_scenery_clearance(Vector3(0, 0, -50)), 150.0), "v14 completed scenery clearance uses the world's configured chunk length")
	generator.profile.chunk_length = 0.0
	check.call(is_zero_approx(generator.completed_scenery_clearance(Vector3.ZERO)), "v14 invalid chunk length supplies no scenery clearance")
	generator.profile = CONTRACTS.profile(14)
	check.call(is_zero_approx(generator.completed_scenery_clearance(Vector3(INF, 0, 0))), "v14 nonfinite eye coordinates supply no scenery clearance")
	generator.profile = null
	check.call(is_zero_approx(generator.completed_scenery_clearance(Vector3.ZERO)), "v14 a missing world profile supplies no scenery clearance")
	generator.free()

static func _check_geometry(check: Callable) -> void:
	for seed_index in range(CONTRACTS.SEEDS.size()):
		var field := WorldField.new(CONTRACTS.SEEDS[seed_index], CONTRACTS.profile())
		var snapshot: Array = []
		for s: float in [0.0, 631.0, 1203.0, 2399.0, 4200.0, 6000.0, 7941.0, 10103.0, 12000.0]:
			snapshot.append([field.road_frame(s), field.road_width(s)])
			for x: float in [-1250.0, -450.0, -150.0, 0.0, 150.0, 450.0, 1250.0]: snapshot.append(field.surface(x, -s))
		snapshot.append(field.landforms.rivers_near(-6000.0, 6000.0))
		check.call(snapshot.hash() == FROZEN[seed_index], "Current terrain, road and water fingerprint remains unchanged for seed %d" % field.world_seed)

static func _check_frozen_road(field: WorldField, check: Callable) -> void:
	var snapshot: Array = []
	for index in range(int(CONTRACTS.LENGTH / CONTRACTS.STEP) + 1):
		var s := index * CONTRACTS.STEP
		snapshot.append([field.road_frame(s), field.road_width(s)])
		if index % 12 != 0: continue
		for lateral: float in [-35.0, 0.0, 35.0]:
			var point := field.road_frame(s) * Vector3(lateral, 0.0, 0.0)
			snapshot.append(field.road_query(point.x, point.z))
	check.call(snapshot.hash() == ROAD_FROZEN[CONTRACTS.SEEDS.find(field.world_seed)], "Current road frames, widths and projections retain their 12km fingerprint for seed %d" % field.world_seed)

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
