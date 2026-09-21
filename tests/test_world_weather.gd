extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	check(WorldWeather.choose(0.049, 0.99, 0.99) == Vector3(1, 0, 0), "Clear excludes rain and fog")
	check(WorldWeather.choose(0.05, 0.5, 0.6) == Vector3(0, 1, 1), "Light thresholds inclusive")
	check(WorldWeather.choose(0.9, 0.8, 0.85) == Vector3(0, 2, 2), "Heavy rain and fog coexist")
	check(WorldWeather.choose(0.9, 0.49, 0.59) == Vector3.ZERO, "Overcast without rain or added fog")
	var a := WorldWeather.new()
	var b := WorldWeather.new()
	a.initialize(42)
	b.initialize(42)
	a.advance(864000)
	for i in range(1000): b.advance(864)
	check(a.capture() == b.capture(), "Multi-segment advancement independent of frame partition")
	a.set_weather(Vector3(0, 2, 2), true)
	a.set_weather(Vector3(1, 0, 0))
	check(a.sample() == Vector3(0, 2, 2), "Transition begins at old appearance")
	a.advance(360)
	check(a.sample().is_equal_approx(Vector3(0.5, 1, 1)), "Transition midpoint interpolates")
	var saved := a.capture()
	check(b.restore(saved) and b.sample() == a.sample(), "Transition roundtrip")
	a.advance(100000)
	b.advance(100000)
	check(a.capture() == b.capture(), "Restored RNG preserves future weather")
	for key in ["source", "target", "remaining", "transition_elapsed", "rng_state"]:
		var bad := saved.duplicate()
		bad[key] = "invalid"
		check(not b.restore(bad), "Reject malformed " + key)
	var bad := saved.duplicate()
	bad.target = Vector3(1, 2, 2)
	check(not WorldWeather.valid_state(bad), "Reject rainy clear target")
	bad = saved.duplicate()
	bad.remaining = NAN
	check(not WorldWeather.valid_state(bad), "Reject NaN time")
	# Real production clock, environment, rain pool and physical roof fixture.
	var world := Node3D.new()
	var bus_count := AudioServer.bus_count
	root.add_child(world)
	var holder := WorldEnvironment.new()
	holder.name = "WorldEnvironment"
	holder.environment = Environment.new()
	world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	world.add_child(sun)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	var clock := WorldClock.new()
	clock.running = false
	world.add_child(clock)
	var material := ShaderMaterial.new()
	if ForestFog.supported():
		material.shader = load("res://world/terrain/forest_fog.gdshader")
	else:
		material.shader = Shader.new()
		material.shader.code = "shader_type spatial; uniform float density = 0.14;"
	clock.register_fog(material)
	clock.weather.set_weather(Vector3(1, 0, 0), true)
	clock.apply_time()
	check(material.get_shader_parameter("density") == 0.0, "Clear removes existing forest fog")
	clock.weather.set_weather(Vector3(0, 2, 2), true)
	clock.apply_time()
	check(holder.environment.fog_depth_end <= 40.0, "Heavy fog fully hides geometry beyond 40 metres")
	var rain := clock.get_node("WeatherRain") as WeatherRain
	rain.listener = camera
	var roof := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 0.5, 50)
	shape.shape = box
	roof.add_child(shape)
	roof.position.y = 3
	world.add_child(roof)
	await physics_frame
	await physics_frame
	check(not rain.ray_hit(Vector3(0, 5, 0), Vector3.ZERO).is_empty(), "Roof intercepts rain path")
	for i in range(100): await physics_frame
	check(is_equal_approx(rain.near_cover.height_at(Vector3.ZERO), 3.25), "Static roof encoded in near height map")
	check(rain.visible_drops == WeatherRain.MAX_DROPS and rain.visible_drops > 70000, "Heavy rain submits dense near and far fields")
	check(rain.fields[1].custom_aabb.size.x >= 192, "Rain covers distant scenery, not a small camera bubble")
	check(not rain.splashes.is_empty() and rain.splashes.size() <= WeatherRain.MAX_SPLASHES, "Rain impacts produce bounded surface splashes")
	check(rain.shelter > 0.8 and rain.low_pass.cutoff_hz < 4000, "Roof muffles rain audio")
	check(rain.voices[1].playing and rain.voices[1].stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Heavy rain loop plays")
	check(rain.visible_drops <= WeatherRain.MAX_DROPS and rain.rays_last_tick <= WeatherRain.MAX_RAYS, "Bounded rain workload")
	roof.position.x = 100
	await physics_frame
	await physics_frame
	check(rain.ray_hit(Vector3(0, 5, 0), Vector3.ZERO).is_empty(), "Moving roof exposes old position")
	roof.queue_free()
	for i in range(90): await physics_frame
	check(rain.near_cover.height_at(Vector3.ZERO) == RainCover.EMPTY_HEIGHT, "Roof removal refreshes cached surface")
	check(rain.splashes.is_empty(), "Splash owners expire after roof removal")
	check(rain.shelter == 0.0, "Open sky restores rain audio")
	var ceiling: Equipment = load("res://equipment/rv_ceiling.tscn").instantiate()
	ceiling.position.y = 3
	ceiling.freeze = true
	world.add_child(ceiling)
	await physics_frame
	await physics_frame
	check(rain.roof_blocks(Vector3.ZERO), "Production RV ceiling provides immediate analytical shelter")
	ceiling.position.x = 12
	await physics_frame
	await physics_frame
	check(not rain.roof_blocks(Vector3.ZERO) and rain.roof_blocks(Vector3(12, 0, 0)), "Moving RV roof mask follows the roof without cache lag")
	ceiling.rotation.z = 0.4
	await physics_frame
	await physics_frame
	check(rain.roof_blocks(Vector3(12, 0, 0)), "Tilted roof still blocks vertical rain")
	ceiling.take_damage(100000)
	await physics_frame
	await physics_frame
	check(not rain.roof_blocks(Vector3(12, 0, 0)), "Destroyed roof stops masking rain immediately")
	var cache := RainCover.new(0.75)
	var query := func(from: Vector3, _to: Vector3) -> Dictionary: return {"position": Vector3(from.x, 5, from.z)}
	check(is_inf(cache.height_at(Vector3.ZERO)), "Unknown cache cells hide rain instead of leaking through roofs")
	cache.update(Vector3.ZERO, RainCover.GRID * RainCover.GRID, query)
	check(cache.height_at(Vector3(-2, 0, -2)) == 5, "Negative world cells wrap correctly")
	cache.update(Vector3(96, 0, 96), RainCover.GRID * RainCover.GRID, query)
	check(is_inf(cache.height_at(Vector3.ZERO)) and cache.height_at(Vector3(96, 0, 96)) == 5, "Old toroidal cells cannot masquerade as new world coordinates")
	cache.reset()
	for tick in range(16):
		cache.update(Vector3(0, 0, -3 * tick), WeatherRain.COVER_NEAR_BUDGET, query)
	var populated := 0
	for row in range(RainCover.GRID):
		for column in range(RainCover.GRID):
			if cache.image.get_pixel(column, row).a > 0.5: populated += 1
	check(populated == RainCover.GRID * RainCover.GRID, "Vehicle motion cannot alias the scan and strand cache rows")
	var gpu_time := rain.simulation_time
	clock.running = true
	paused = true
	var frozen := clock.weather.capture()
	await process_frame
	await process_frame
	check(clock.weather.capture() == frozen and rain.simulation_time == gpu_time, "Scene pause freezes weather and GPU rain time")
	paused = false
	clock.running = false
	clock.day_length_minutes = 1
	var remaining := clock.weather.remaining
	clock.advance(0.1)
	check(is_equal_approx(remaining - clock.weather.remaining, 144), "Weather follows accelerated clock")
	world.queue_free()
	await process_frame
	check(AudioServer.bus_count == bus_count, "Weather bus released with world")
	if failures.is_empty(): print("PASS: weather selection, transitions, persistence, clock, fog, moving roof and bounded rain")
	quit(0 if failures.is_empty() else 1)
