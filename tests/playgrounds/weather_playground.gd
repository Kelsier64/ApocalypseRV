extends Node3D
## Judge the weather in the generated world: rain, fog, sky and time of day,
## the roof keeping rain and dust out of the cabin, rain leaning in the wind,
## and the dust haze, grit and clouds a strong wind raises. Play with the
## normal controls; everything else is in the Esc Playground tab.

const SCENARIOS := ["Roadside", "Cabin", "Driver seat", "Dust storm"]
const WEATHERS := RVTerminalCommands.WEATHER_PRESETS
const START_WEATHER := "overcast"
const START_HOUR := 12.0
## Road distance of the parked RV from the start of the route.
const START_S := 60.0
const METRICS_SECONDS := 5.0

var controls := PlaygroundControls.new()
var main: Node3D
var clock: WorldClock
var rv: Chassis
var player: CharacterBody3D
var _weather := WEATHERS.keys().find(START_WEATHER)
var _metrics_elapsed := 0.0
var _frames := 0
var _frame_total := 0.0
var _max_rays := 0


func _ready() -> void:
	get_window().title = "ApocalypseRV - Weather"
	var scenario := PlaygroundControls.scenario(SCENARIOS[0])
	var world_seed := 42
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): world_seed = argument.trim_prefix("--seed=").to_int()
	print("PLAYGROUND scenario=%s seed=%d" % [scenario, world_seed])
	main = load("res://world/test_world.tscn").instantiate()
	var generator := main.get_node("WorldGenerator")
	generator.world_seed = world_seed
	generator.profile = WorldProfile.new()
	# Park on the road and stream the world around the RV from the first frame.
	var frame := WorldField.new(world_seed, generator.profile).road_frame(START_S)
	main.get_node("NewRv").transform = Transform3D.IDENTITY
	rv = main.get_node("NewRv/Chassis")
	rv.transform = frame
	rv.position.y += 1.8
	player = main.get_node("Player")
	player.position = rv.position + frame.basis.x * 4.0
	get_tree().node_added.connect(_remove_monster)
	add_child(main)
	clock = main.get_node("WorldClock")
	# Weather stays where the Playground tab puts it. The clock runs so gusts move.
	clock.weather_running = false
	clock.set_time(1, START_HOUR)
	# Weather presets start a new segment, which would reroll natural wind.
	clock.wind.set_override(WorldWind.STRONG)
	if scenario == "Dust storm":
		# Clear and dry: a gale over the driest landform, wherever the RV parked.
		_weather = WEATHERS.keys().find("clear")
		clock.wind.set_override(WorldWind.GALE)
		clock.landform_override = _driest_landform()
	_apply_weather()
	rv.handbrake = true
	rv.set_gear(0)
	for enemy in get_tree().get_nodes_in_group(Groups.MONSTERS): enemy.queue_free()
	_build_controls(scenario)
	await main.wait_for_play()
	# Let the chassis settle on its wheels before placing the player on or in it.
	for i in range(Engine.physics_ticks_per_second): await get_tree().physics_frame
	_place_player(scenario)


func _place_player(scenario: String) -> void:
	var aisle := rv.to_global(Vector3(0.25, rv.get_node("Audio").CABIN.position.y + 0.1, 1.65))
	player.velocity = Vector3.ZERO
	match scenario:
		"Cabin", "Driver seat":
			player.global_position = aisle
			player.rotation.y = rv.global_rotation.y
			if scenario == "Driver seat":
				await get_tree().physics_frame
				rv.set_engine_running(true)
				rv.get_node("DriverSeat").interact_hold(player)
		_:
			var beside := rv.to_global(Vector3(3.6, 0.0, 1.65))
			var ground: float = main.get_node("WorldGenerator").field.height_at(beside.x, beside.z)
			player.global_position = Vector3(beside.x, ground + 0.1, beside.z)
			player.rotation.y = rv.global_rotation.y + PI / 2.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_controls(scenario: String) -> void:
	add_child(controls)
	controls.scenarios(SCENARIOS, scenario)
	controls.note("Play normally: walk, board the RV, drive. Monsters are removed. Weather stays where this tab puts it until you turn on Natural weather. The clock runs so gusts move; stop it to hold the light.")
	controls.section("Weather")
	controls.choice("Weather", PackedStringArray(WEATHERS.keys().map(func(key: String) -> String: return key.capitalize())), _weather, func(index: int) -> void:
		_weather = index
		_apply_weather())
	controls.toggle("Natural weather", false, func(on: bool) -> void: clock.weather_running = on)
	controls.button("Next weather segment", func() -> void:
		clock.weather.advance(clock.weather.remaining)
		clock.apply_time())
	controls.readout("Now", func() -> String: return clock.weather.description())
	controls.section("Time")
	controls.toggle("Clock runs", true, func(on: bool) -> void: clock.running = on)
	controls.slider("Hour", 0.0, 24.0, 0.25, START_HOUR, func(hour: float) -> void: clock.set_time(clock.day_number(), fmod(hour, 24.0)))
	controls.readout("Clock", func() -> String: return "Day %d, %02d:%02d" % [clock.day_number(), floori(clock.hour_of_day()), floori(fmod(clock.hour_of_day(), 1.0) * 60.0)])
	controls.section("Wind")
	controls.note("Wind starts overridden so weather changes do not reroll it. Landform sets the ground the dust reads, wherever you are. Wind has no sound and does not push the RV yet.")
	var tiers := PackedStringArray(["Natural"])
	for tier: String in WorldWind.DESCRIPTIONS: tiers.append(tier)
	controls.choice("Strength", tiers, clock.wind.override_tier + 1, func(index: int) -> void:
		clock.wind.set_override(index - 1)
		clock.apply_time())
	controls.slider("Heading (deg)", 0.0, 359.0, 1.0, 0.0, func(value: float) -> void: clock.wind.override_heading = deg_to_rad(value))
	controls.button("Natural heading", func() -> void: clock.wind.override_heading = NAN)
	var kinds := PackedStringArray(["Where you are"])
	for kind: String in TerrainLandforms.KINDS: kinds.append(kind.capitalize())
	controls.choice("Landform", kinds, clock.landform_override + 1, func(index: int) -> void: clock.landform_override = index - 1)
	controls.readout("Wind", func() -> String: return "%s (strength %.2f)" % [clock.wind.description(), clock.wind.strength()])
	controls.readout("Speed / gust", func() -> String: return "%.1f m/s / %.2f" % [clock.wind_velocity.length(), clock.wind.gust(clock.elapsed_seconds)])
	controls.readout("Heading", func() -> String: return "%03d deg" % (roundi(rad_to_deg(clock.wind.heading(clock.elapsed_seconds))) % 360))
	controls.readout("Ground", _landform_text)
	controls.readout("Dust", func() -> String: return "%.2f with gusts, haze %.2f, haze ends at %d m" % [clock.dust, clock.haze_dust, roundi(clock.environment.fog_depth_end)])
	controls.section("RV")
	controls.note("A broken roof lets rain and dust into the cabin. It stays broken; Restart brings it back.")
	controls.button("Break middle roof", func() -> void:
		var roof := rv.get_node_or_null("RoofMiddle")
		if roof != null: roof.take_damage(100000.0))
	controls.section("Rain cost")
	controls.readout("Drops submitted", func() -> String: return str(_rain().visible_drops))
	controls.readout("Dust particles", func() -> String: return str((clock.get_node("WeatherDust") as WeatherDust).visible_particles))
	controls.readout("Cover rays", func() -> String: return str(_rain().rays_last_tick))
	controls.readout("Frame", func() -> String: return "%.1f ms" % (1000.0 / maxf(Engine.get_frames_per_second(), 1.0)))


func _apply_weather() -> void:
	clock.weather.set_weather(WEATHERS.values()[_weather], true)
	clock.apply_time()


func _rain() -> WeatherRain:
	return clock.get_node("WeatherRain") as WeatherRain


func _remove_monster(node: Node) -> void:
	if node is Monster: node.queue_free.call_deferred()


func _driest_landform() -> int:
	var driest := 0
	for kind in range(TerrainLandforms.KINDS.size()):
		if WorldWind.dryness_for(Vector3(kind, kind, 0)) > WorldWind.dryness_for(Vector3(driest, driest, 0)): driest = kind
	return driest


func _appearance() -> Vector3:
	if clock.landform_override >= 0: return Vector3(clock.landform_override, clock.landform_override, 0)
	var viewer := get_viewport().get_camera_3d()
	if viewer == null: return Vector3.ZERO
	return main.get_node("WorldGenerator").field.landforms.appearance_at(-viewer.global_position.z)


func _landform_text() -> String:
	var a := _appearance()
	var kind: String = TerrainLandforms.KINDS[int(a.x)].capitalize()
	if a.z > 0.0: kind += " > %s %.0f%%" % [TerrainLandforms.KINDS[int(a.y)].capitalize(), a.z * 100.0]
	return "%s, dryness %.2f, exposure %.2f" % [kind, WorldWind.dryness_for(a), WorldWind.exposure_for(a)]


## Logs rain cost every few seconds so runs can be compared from the log.
func _process(delta: float) -> void:
	if clock == null: return
	_metrics_elapsed += delta
	_frames += 1
	_frame_total += delta
	_max_rays = maxi(_max_rays, _rain().rays_last_tick)
	if _metrics_elapsed < METRICS_SECONDS: return
	print("WEATHER METRICS ", clock.weather.description(), " dust=", snappedf(clock.dust, 0.01), " haze_dust=", snappedf(clock.haze_dust, 0.01), " submitted_particles=", _rain().visible_drops, " dust_particles=", (clock.get_node("WeatherDust") as WeatherDust).visible_particles, " max_rays=", _max_rays, " frame_ms=", snappedf(_frame_total * 1000.0 / _frames, 0.01))
	_metrics_elapsed = 0.0
	_frames = 0
	_frame_total = 0.0
	_max_rays = 0


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_remove_monster): get_tree().node_added.disconnect(_remove_monster)
