extends RefCounted
## Atmosphere tuning and streamed visibility must not become weather state.
const DEFAULT = preload("res://world/world_atmosphere_profile.tres")
const GUARD = preload("res://world/stream_visibility_guard.gd")
const TERRAIN = preload("res://tests/support/terrain_contracts.gd")

static func run(world: Node3D, check: Callable) -> void:
	_check_profile(check)
	_check_guard(check)
	_check_weather(check)
	_check_owners(world, check)

static func _check_profile(check: Callable) -> void:
	var custom := DEFAULT.duplicate() as WorldAtmosphereProfile
	custom.landscape_begin = 40.0
	custom.clear_begin = 80.0
	custom.landscape_end = 300.0
	custom.weather_begin = 10.0
	custom.light_end = 250.0
	custom.medium_end = 120.0
	custom.heavy_end = 50.0
	custom.distance_curve = 1.5
	custom.white_strength = 0.7
	custom.global_density = 0.004
	custom.rain_density = 0.001
	custom.local_density = 0.2
	var clear := custom.mist(Vector3.ZERO)
	var rain := custom.mist(Vector3(0, 2, 0.25))
	check.call(is_equal_approx(clear.depth_begin, 40.0) and is_equal_approx(clear.depth_end, 300.0) and is_equal_approx(clear.depth_curve, 1.5) and is_equal_approx(clear.white_strength, 0.7), "Atmosphere resource controls landscape interval, curve and white strength")
	check.call(is_equal_approx(custom.mist(Vector3(1, 0, 0)).depth_begin, 80.0) and is_equal_approx(custom.mist(Vector3(0.5, 0, 0.25)).depth_begin, 35.0), "Sunny onset is separately tunable and blends continuously into weather haze")
	check.call(is_equal_approx(rain.depth_begin, 25.0) and is_equal_approx(rain.depth_end, 275.0) and is_equal_approx(rain.global_density, 0.003) and is_equal_approx(rain.local_density, 0.1), "Atmosphere resource preserves weather interpolation while tuning rain and local scattering")
	check.call(is_equal_approx(custom.mist(Vector3(0, 0, 1)).depth_end, 120.0) and is_equal_approx(custom.mist(Vector3(0, 0, 2)).depth_end, 50.0), "Atmosphere resource controls medium and heavy weather endpoints")
	custom.light_end = 500.0
	check.call(is_equal_approx(custom.mist(Vector3(0, 0, 0.5)).depth_end, 300.0), "Weather tuning cannot expose scenery beyond the landscape terminal cap")
	custom.volume_max_length = 80.0
	custom.volume_end_ratio = 0.4
	check.call(is_equal_approx(custom.volume_length(150.0), 60.0) and is_equal_approx(custom.volume_length(300.0), 80.0) and is_equal_approx(custom.volume_length(0.0), 0.1), "Atmosphere resource controls scattering integration with a positive minimum and maximum")
	check.call(DEFAULT.day_color(Vector3.ZERO).is_equal_approx(Color("a4afb0")) and DEFAULT.day_color(Vector3(1, 0, 0)).is_equal_approx(Color("d0cbb8")) and DEFAULT.day_color(Vector3(0, 0, 0.5)).is_equal_approx(Color("c3cbc8")), "Overcast, sunny and light-fog daytime terminal colors remain distinct")
	custom.overcast_day_color = Color("405060")
	custom.clear_day_color = Color("c0a080")
	custom.day_mist_color = Color("e0e8e0")
	var halfway_color := Color("405060").lerp(Color("c0a080"), 0.5).lerp(Color("e0e8e0"), 0.5)
	check.call(custom.day_color(Vector3(0.5, 2, 0.25)).is_equal_approx(halfway_color) and custom.day_color(Vector3(1, 0, 2)).is_equal_approx(Color("e0e8e0")), "Authored day colors blend clear and fog transitions without changing with rainfall")
	var bounded := true
	for clear_weight: float in [0.0, 0.5, 1.0]:
		var previous_end := INF
		for fog: float in [0.0, 0.25, 0.5, 0.625, 0.75, 1.0, 1.5, 2.0]:
			var sample := DEFAULT.mist(Vector3(clear_weight, 0, fog))
			bounded = bounded and sample.depth_begin >= 0.0 and sample.depth_begin < sample.depth_end and sample.depth_end <= 230.0 and sample.depth_end <= previous_end
			previous_end = sample.depth_end
	check.call(bounded, "Sunny, overcast and interpolated fog profiles retain ordered intervals and only shorten the permanent terminal cap")
	for strength: float in [0.5, 1.0, 2.0]:
		var before := DEFAULT.mist(Vector3(0, 0, strength - 0.00001))
		var after := DEFAULT.mist(Vector3(0, 0, strength + 0.00001))
		var before_color: Color = DEFAULT.day_color(Vector3(0, 0, strength - 0.00001))
		var after_color: Color = DEFAULT.day_color(Vector3(0, 0, strength + 0.00001))
		check.call(absf(before.depth_begin - after.depth_begin) < 0.01 and absf(before.depth_end - after.depth_end) < 0.01 and before_color.is_equal_approx(after_color), "Fog onset, terminal distance and day color remain continuous across tier %.1f" % strength)
	for fixture: Array in [[Vector3(1, 2, 0), 0.25, Vector3(0.5, 2, 0.25)], [Vector3(1, 0, 0), 1.0, Vector3(0, 0, 1)], [Vector3(0, 1, 2), 0.5, Vector3(0, 1, 2)]]:
		check.call(WorldAtmosphereProfile.visual_conditions(fixture[0], fixture[1]).is_equal_approx(fixture[2]), "Visual deviation blends clear skies and fog without weakening stronger natural weather")
	check.call(is_equal_approx(DEFAULT.landscape_end, 230.0) and is_equal_approx(DEFAULT.local_density, 0.14), "Duplicated atmosphere tuning leaves the shared default resource unchanged")

static func _check_guard(check: Callable) -> void:
	var custom := DEFAULT.duplicate() as WorldAtmosphereProfile
	custom.landscape_end = 420.0
	custom.stream_margin = 12.0
	custom.stream_reveal_speed = 7.0
	var guard := GUARD.new()
	check.call(is_inf(guard.limit) and is_equal_approx(guard.update(INF, 0.0, custom), 420.0), "Fresh visibility guard adopts the owning profile cap without a hidden 230m ceiling")
	check.call(is_equal_approx(guard.update(100.0, NAN, custom), 88.0), "Visibility guard closes immediately even when frame delta is invalid")
	for invalid: float in [0.0, -1.0, INF, NAN]:
		check.call(is_equal_approx(guard.update(INF, invalid, custom), 88.0), "Visibility guard never reveals coverage with zero, negative or nonfinite real delta")
	check.call(is_equal_approx(guard.update(INF, 0.5, custom), 91.5) and is_equal_approx(guard.update(INF, 100.0, custom), 420.0), "Missing camera or coverage opens gradually at the profile's real-time speed and stops at its cap")
	check.call(is_equal_approx(guard.update(NAN, 1.0, custom), 1.0), "Invalid coverage fails closed to positive minimum visibility")
	check.call(is_equal_approx(guard.update(-INF, 1.0, custom), 1.0) and is_equal_approx(guard.update(0.0, 1.0, custom), 1.0), "Negative or uncovered clearance cannot invert the fog interval")
	check.call(is_equal_approx(guard.update(80.0, 2.0, custom), 15.0) and is_equal_approx(guard.update(20.0, 0.0, custom), 8.0), "Visibility guard recovers in real seconds and tightens again without waiting for a frame")
	custom.landscape_end = 5.0
	check.call(is_equal_approx(guard.update(INF, 0.0, custom), 5.0), "Reducing a live profile cap closes the visibility guard immediately")
	var one_step := GUARD.new()
	var split_steps := GUARD.new()
	one_step.update(12.0, 0.0, DEFAULT)
	split_steps.update(12.0, 0.0, DEFAULT)
	for _index in range(10): split_steps.update(INF, 0.1, DEFAULT)
	check.call(is_equal_approx(one_step.update(INF, 1.0, DEFAULT), split_steps.limit), "Splitting real frame time preserves the visibility recovery rate")

static func _check_weather(check: Callable) -> void:
	# Independent RNG oracle pins draw order, duration and natural weather tiers.
	# Rendering/profile sampling may be repeated between transitions freely.
	for seed_value: int in [42, 314159]:
		var weather := WorldWeather.new()
		weather.initialize(seed_value)
		var oracle := RandomNumberGenerator.new()
		oracle.seed = seed_value ^ 0x57454154484552
		var duration := oracle.randf_range(8640.0, 17280.0)
		check.call(weather.capture() == {"source": Vector3.ZERO, "target": Vector3.ZERO, "transition_elapsed": 720.0, "remaining": duration, "rng_state": oracle.state}, "Weather capture keeps the exact five-field format, initialization duration and isolated RNG seed")
		for _cycle in range(8):
			var saved := weather.capture()
			for sample_index in range(4):
				var conditions := WorldAtmosphereProfile.visual_conditions(weather.sample(), sample_index * 0.25)
				DEFAULT.mist(conditions)
				DEFAULT.day_color(conditions)
			check.call(weather.capture() == saved, "Atmosphere and weather sampling do not consume natural RNG or transition time")
			# The outgoing transition completes before its duration expires.
			var previous := weather.target
			var clear_roll := oracle.randf()
			var rain_roll := oracle.randf()
			var fog_roll := oracle.randf()
			var target := Vector3(1, 0, 0) if clear_roll < 0.05 else Vector3(0, 0 if rain_roll < 0.5 else (1 if rain_roll < 0.8 else 2), 0 if fog_roll < 0.2 else (0.5 if fog_roll < 0.6 else (1 if fog_roll < 0.85 else 2)))
			duration = oracle.randf_range(8640.0, 17280.0)
			weather.advance(weather.remaining)
			check.call(weather.capture() == {"source": previous, "target": target, "transition_elapsed": 0.0, "remaining": duration, "rng_state": oracle.state}, "Natural weather preserves exact RNG draw order, selected tiers and timing across atmosphere queries")
			var restored := WorldWeather.new()
			check.call(restored.restore(weather.capture()), "Weather capture remains directly restorable without atmosphere fields")
			weather.advance(360.0)
			restored.advance(360.0)
			check.call(weather.capture() == restored.capture() and weather.sample().is_equal_approx(previous.lerp(target, 0.5)), "Weather save/restore continues the unchanged 720-second transition exactly")

static func _owner(world: Node3D, atmosphere: WorldAtmosphereProfile) -> Node3D:
	var host := Node3D.new()
	host.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(host)
	var holder := WorldEnvironment.new()
	holder.name = "WorldEnvironment"
	holder.environment = Environment.new()
	host.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	host.add_child(sun)
	var clock := WorldClock.new()
	clock.name = "WorldClock"
	clock.atmosphere = atmosphere
	clock.running = false
	clock.weather_running = false
	host.add_child(clock)
	clock.set_time(1, 12.0)
	return host

static func _check_owners(world: Node3D, check: Callable) -> void:
	var default_clock := WorldClock.new()
	var another_default := WorldClock.new()
	check.call(default_clock.atmosphere == DEFAULT and another_default.atmosphere == DEFAULT, "Default clocks reference the same authored atmosphere resource")
	default_clock.free()
	another_default.free()
	var first_profile := DEFAULT.duplicate() as WorldAtmosphereProfile
	first_profile.landscape_end = 420.0
	first_profile.cull_buffer = 23.0
	first_profile.day_mist_color = Color("a1b2c3")
	first_profile.overcast_day_color = Color("a1b2c3")
	first_profile.clear_day_color = Color("a1b2c3")
	first_profile.night_mist_color = Color("010203")
	first_profile.local_density = 0.22
	first_profile.overcast_sun_energy = 0.31
	var second_profile := DEFAULT.duplicate() as WorldAtmosphereProfile
	var first := _owner(world, first_profile)
	var second := _owner(world, second_profile)
	var shared := _owner(world, first_profile)
	var clock := first.get_node("WorldClock") as WorldClock
	var other := second.get_node("WorldClock") as WorldClock
	var shared_clock := shared.get_node("WorldClock") as WorldClock
	check.call(is_equal_approx(clock.environment.fog_depth_end, 420.0) and is_equal_approx(other.environment.fog_depth_end, 230.0) and clock.environment.fog_light_color.is_equal_approx(Color("a1b2c3")) and is_equal_approx(clock.sun.light_energy, 0.31) and is_equal_approx(other.sun.light_energy, 0.45), "Each clock uses its own atmosphere resource for the terminal interval, daylight color and sun energy")
	clock.set_time(1, 0.0)
	check.call(clock.environment.fog_light_color.is_equal_approx(Color("010203")), "Clock uses the owning atmosphere's night color")
	clock.set_time(1, 12.0)
	var saved := clock.weather.capture()
	var material := ShaderMaterial.new()
	material.shader = load("res://world/terrain/white_mist.gdshader") as Shader
	clock.register_fog(material)
	check.call(is_equal_approx(float(material.get_shader_parameter("density")), 0.22), "Mist registration reads the owning profile's local density")
	clock.set_deviation_fog(1.0)
	clock.set_deviation_fog(0.0)
	first_profile.local_density = 0.18
	clock.apply_time()
	check.call(clock.weather.capture() == saved and is_equal_approx(float(material.get_shader_parameter("density")), 0.18), "Render refresh, profile tuning and deviation leave natural weather capture and RNG untouched")
	clock.unregister_fog(material)
	first_profile.landscape_end = 390.0
	clock.apply_time()
	shared_clock.apply_time()
	other.apply_time()
	check.call(is_equal_approx(clock.environment.fog_depth_end, 390.0) and is_equal_approx(shared_clock.environment.fog_depth_end, 390.0) and is_equal_approx(other.environment.fog_depth_end, 230.0) and is_equal_approx(DEFAULT.landscape_end, 230.0), "Explicitly shared profiles update both owners while independently duplicated profiles and defaults stay isolated")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8, 20, 6)
	var poses: Array = [Transform3D(Basis.IDENTITY, Vector3(1, 0, 1))]
	for host: Node3D in [first, second]:
		var chunk := ChunkGenerator.new()
		chunk.field = WorldField.new(42, TERRAIN.profile(14))
		host.add_child(chunk)
		var instances := ForestScenery.batch(chunk, "ForestBrush0", mesh, poses)
		var node: MultiMeshInstance3D = instances[poses[0].origin].node
		var expected := 390.0 + 23.0 if host == first else 238.0
		var radius := mesh.get_aabb().size.length() * 0.5
		check.call(is_equal_approx(node.visibility_range_end - radius - node.visibility_range_end_margin, expected), "Forest culling resolves its owning clock's atmosphere terminal cap and buffer")
	first.free()
	second.free()
	shared.free()
