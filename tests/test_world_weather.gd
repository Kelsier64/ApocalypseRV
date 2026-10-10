extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	check(WorldWeather.choose(0.049, 0.99, 0.99) == Vector3(1, 0, 0), "Clear excludes rain and fog")
	check(WorldWeather.choose(0.05, 0.5, 0.2) == Vector3(0, 1, 0.5), "Light rain and new light fog thresholds inclusive")
	check(WorldWeather.choose(0.9, 0.8, 0.85) == Vector3(0, 2, 2), "Heavy rain and fog coexist")
	check(WorldWeather.choose(0.9, 0.49, 0.199) == Vector3.ZERO, "Overcast without rain or added fog")
	for boundary in [[0.199, 0.0], [0.2, 0.5], [0.599, 0.5], [0.6, 1.0], [0.849, 1.0], [0.85, 2.0]]:
		check(WorldWeather.choose(0.05, 0.0, boundary[0]).z == boundary[1], "Fog threshold at " + str(boundary[0]))
	var fog_counts := {0.0: 0, 0.5: 0, 1.0: 0, 2.0: 0}
	for index in range(100):
		var selected := WorldWeather.choose(0.5, 0.0, (index + 0.5) / 100.0).z
		fog_counts[selected] += 1
	check(fog_counts == {0.0: 20, 0.5: 40, 1.0: 25, 2.0: 15}, "Non-clear fog distribution is exactly 20/40/25/15 percent")
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
	for tier in [0.0, 0.5, 1.0, 2.0]:
		var state := saved.duplicate()
		state.target = Vector3(0, 1, tier)
		check(WorldWeather.valid_state(state), "Accept discrete fog target " + str(tier))
	for invalid_fog in [-0.1, 0.25, 0.75, 1.5, 2.1, NAN, INF]:
		var state := saved.duplicate()
		state.target = Vector3(0, 0, invalid_fog)
		check(not WorldWeather.valid_state(state), "Reject non-tier fog target " + str(invalid_fog))
	for fractional_axis in [Vector3(0.5, 0, 0.5), Vector3(0, 0.5, 0.5)]:
		var state := saved.duplicate()
		state.target = fractional_axis
		check(not WorldWeather.valid_state(state), "New half-tier fog does not permit fractional clear or rain targets")
	for source_fog in [0.0, 0.25, 0.5, 0.75, 1.5, 2.0]:
		var state := saved.duplicate()
		state.source = Vector3(0.25, 0.5, source_fog)
		state.target = Vector3(0, 0, 0.5)
		check(WorldWeather.valid_state(state), "Interpolated fog source remains valid " + str(source_fog))
	for invalid_source in [-0.1, 2.1, NAN, INF]:
		var state := saved.duplicate()
		state.source = Vector3(0, 0, invalid_source)
		check(not WorldWeather.valid_state(state), "Reject invalid fog source " + str(invalid_source))
	var light_transition := WorldWeather.new()
	light_transition.initialize(42)
	light_transition.set_weather(Vector3(0, 0, 0.5))
	light_transition.advance(WorldWeather.TRANSITION / 2.0)
	check(light_transition.sample().is_equal_approx(Vector3(0, 0, 0.25)), "New light fog transition midpoint remains fractional")
	var interrupted_light := light_transition.capture()
	light_transition.set_weather(Vector3(0, 0, 1))
	check(light_transition.sample().is_equal_approx(Vector3(0, 0, 0.25)), "Interrupting a light fog transition preserves current appearance")
	check(WorldWeather.valid_state(light_transition.capture()), "Interrupted fractional fog source can be saved")
	var restored_light := WorldWeather.new()
	check(restored_light.restore(interrupted_light), "New half-tier target restores without schema version")
	restored_light.advance(WorldWeather.TRANSITION / 2.0)
	check(restored_light.sample() == Vector3(0, 0, 0.5), "Restored light fog transition completes at half-tier")
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
	clock.set_time(1, 12.0)
	clock.weather.set_weather(Vector3.ZERO, true)
	clock.apply_time()
	check(is_equal_approx(material.get_shader_parameter("density"), 0.14), "Overcast retains baseline local fog")
	clock.weather.set_weather(Vector3(0, 0, 0.5))
	clock.weather.advance(WorldWeather.TRANSITION / 2.0)
	clock.apply_time()
	check(is_equal_approx(material.get_shader_parameter("density"), 0.07), "Local volumetric fog fades halfway at light transition midpoint")
	check(is_equal_approx(holder.environment.volumetric_fog_density, 0.00075), "Global volumetric fog shares the light transition fade")
	var streamed_material := material.duplicate() as ShaderMaterial
	streamed_material.set_shader_parameter("density", 1.0)
	clock.register_fog(streamed_material)
	check(is_equal_approx(streamed_material.get_shader_parameter("density"), material.get_shader_parameter("density")), "New chunk material immediately matches current fractional fog density")
	clock.apply_time()
	check(is_equal_approx(streamed_material.get_shader_parameter("density"), material.get_shader_parameter("density")), "Applying time preserves newly registered fog density")
	clock.unregister_fog(streamed_material)
	for tier in [[0.5, 220.0, "小霧"], [1.0, 110.0, "中霧"], [2.0, 38.0, "大霧"]]:
		clock.weather.set_weather(Vector3(0, 0, tier[0]), true)
		clock.apply_time()
		check(is_equal_approx(holder.environment.fog_depth_begin, 8.0) and is_equal_approx(holder.environment.fog_depth_end, tier[1]), "Fog tier has correct depth range: " + tier[2])
		check(clock.weather.description() == "陰天・" + tier[2] and clock.weather_label.text == clock.weather.description(), "Fog tier description reaches HUD: " + tier[2])
		check(holder.environment.volumetric_fog_density == 0.0 and material.get_shader_parameter("density") == 0.0, "Light and denser weather fog fully remove global and local volumetric fog: " + tier[2])
	for legacy_tier in [1.0, 2.0]:
		# Existing checkpoint weather has no schema version. Numeric 1 retains
		# its old 110 m appearance, now named medium; numeric 2 stays heavy.
		var legacy := {"source": Vector3(0, 0, legacy_tier), "target": Vector3(0, 0, legacy_tier), "transition_elapsed": WorldWeather.TRANSITION, "remaining": 10000.0, "rng_state": saved.rng_state}
		check(clock.weather.restore(legacy), "Accept legacy unversioned fog state " + str(legacy_tier))
		clock.apply_time()
		check(clock.weather.sample().z == legacy_tier and is_equal_approx(holder.environment.fog_depth_end, 110.0 if legacy_tier == 1 else 38.0), "Legacy numeric fog keeps its original depth appearance")
		var original_color := Color("a4aca9").lerp(Color("535c5b"), legacy_tier / 2.0)
		check(holder.environment.fog_light_color.is_equal_approx(original_color), "Legacy numeric fog keeps its original mist color")
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
	var ceiling: RVStructurePanel = load("res://equipment/rv_ceiling.tscn").instantiate()
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
	# Three opening panels contribute twelve solid rectangles. The physical
	# opening must stay exposed in both rain masks and cabin fog exclusions.
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.x = 24.0
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	await physics_frame
	await physics_frame
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	for index in range(3):
		slots.replace_panel("roof_" + str(index), "rv_ceiling_hatch", 120.0)
	await physics_frame
	await physics_frame
	rain._update_roofs(camera.global_position)
	check(rain.roof_transforms.size() == 12, "Three roof openings retain all twelve solid rain-mask rectangles")
	for index in range(3):
		var hatch: RVStructurePanel = slots.occupant("roof_" + str(index))
		var hole := hatch.to_global(Vector3(-1.075, -1.0, 0))
		var solid := hatch.to_global(Vector3(1.0, -1.0, 0))
		check(not rain.roof_blocks(hole) and rain.roof_blocks(solid), "Rain passes only through the left opening: " + str(index))
		check(rain.ray_hit(hole + Vector3.UP * 2, hole).is_empty(), "No invisible collision closes the opening: " + str(index))
		var air: Node3D = hatch.get_node("CabinAir")
		check(not air.shelters(Vector3(-1.075, -1, 0)) and air.shelters(Vector3(1, -1, 0)), "Fog exclusion follows solid material and leaves the opening exposed: " + str(index))
	var middle: RVStructurePanel = slots.occupant("roof_1")
	middle.take_damage(999.0)
	await physics_frame
	rain._update_roofs(camera.global_position)
	check(not rain.roof_blocks(rv.to_global(Vector3(1, 1.6, 0))) and rain.roof_blocks(rv.to_global(Vector3(1, 1.6, -4))) and rain.roof_blocks(rv.to_global(Vector3(1, 1.6, 4))), "A destroyed roof segment admits rain without removing neighbouring shelter")
	rv.position.x += 8
	rv.rotation.y = PI * 0.5
	await physics_frame
	rain._update_roofs(camera.global_position)
	var moved: RVStructurePanel = slots.occupant("roof_0")
	check(not rain.roof_blocks(moved.to_global(Vector3(-1.075, -1, 0))) and rain.roof_blocks(moved.to_global(Vector3(1, -1, 0))), "Roof opening and solid shelter follow vehicle translation and rotation")
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
