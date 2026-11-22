extends "res://tests/playgrounds/day_night_playground.gd"
const PRESETS := [Vector3.ZERO, Vector3(0, 1, 0), Vector3(0, 2, 0), Vector3(0, 0, WorldWeather.FOG_LIGHT), Vector3(0, 0, WorldWeather.FOG_MEDIUM), Vector3(0, 0, WorldWeather.FOG_HEAVY), Vector3(1, 0, 0), Vector3(0, 2, WorldWeather.FOG_HEAVY)]
var preset := 0
var metrics_elapsed := 0.0
var frame_samples := 0
var frame_total := 0.0
var max_rays := 0
var controls := PlaygroundControls.new()
## -1 samples the landform under the camera; otherwise a TerrainLandforms.KINDS index.
var landform := -1

func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - Weather Validation"
	clock.weather_running = false
	clock.set_time(1, 12)
	# Weather presets start new segments, which would reroll natural wind.
	clock.wind.set_override(WorldWind.STRONG)
	stage = 0
	_view()
	_build_wind_controls()
	time_controls.text += "\n6 weather presets | 7 rain | 8 fog | 9 clear/overcast | 0 auto weather | Backspace destroy roof"
	# Audio must follow the observer in this detached-camera validation scene.
	clock.get_node("WeatherRain").listener = camera
	if "--heavy-rain" in OS.get_cmdline_user_args():
		preset = 2
		clock.weather.set_weather(PRESETS[preset], true)
		clock.apply_time()

func _build_wind_controls() -> void:
	add_child(controls)
	controls.section("Wind")
	controls.note("Phase 1 has no dust or wind visuals yet; read the values below. Wind starts overridden to strong so weather presets do not reroll it.")
	var tiers := PackedStringArray(["Natural"])
	for tier: String in WorldWind.DESCRIPTIONS: tiers.append(tier)
	controls.choice("Wind strength", tiers, clock.wind.override_tier + 1, func(index: int): clock.wind.set_override(index - 1))
	controls.slider("Heading (deg)", 0.0, 359.0, 1.0, 0.0, func(value: float): clock.wind.override_heading = deg_to_rad(value))
	controls.button("Natural heading", func(): clock.wind.override_heading = NAN)
	var kinds := PackedStringArray(["Under the camera"])
	for kind: String in TerrainLandforms.KINDS: kinds.append(kind.capitalize())
	controls.choice("Landform", kinds, 0, func(index: int): landform = index - 1)
	controls.readout("Wind", func(): return "%s (strength %.2f)" % [clock.wind.description(), clock.wind.strength()])
	controls.readout("Speed / gust", func(): return "%.1f m/s / %.2f" % [clock.wind.speed(clock.elapsed_seconds, WorldWind.exposure_for(_appearance())), clock.wind.gust(clock.elapsed_seconds)])
	controls.readout("Heading", func(): return "%03d deg" % (roundi(rad_to_deg(clock.wind.heading(clock.elapsed_seconds))) % 360))
	controls.readout("Landform", func(): return _landform_text())
	controls.readout("Dust", func(): return "%.2f" % clock.wind.dust_at(clock.elapsed_seconds, _appearance()))
	controls.readout("Weather", func(): return clock.weather.description())

func _appearance() -> Vector3:
	if landform >= 0: return Vector3(landform, landform, 0)
	var viewer := get_viewport().get_camera_3d()
	var generator := main.get_node("WorldGenerator")
	if viewer == null: return Vector3.ZERO
	return generator.field.landforms.appearance_at(-viewer.global_position.z)

func _landform_text() -> String:
	var a := _appearance()
	var kind: String = TerrainLandforms.KINDS[int(a.x)]
	if a.z > 0.0: kind += " > %s %.0f%%" % [TerrainLandforms.KINDS[int(a.y)], a.z * 100.0]
	return "%s, dryness %.2f, exposure %.2f" % [kind, WorldWind.dryness_for(a), WorldWind.exposure_for(a)]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var value := clock.weather.target
		match event.keycode:
			KEY_6:
				preset = (preset + 1) % PRESETS.size()
				value = PRESETS[preset]
			KEY_7: value = Vector3(0, fmod(value.y + 1, 3), value.z)
			KEY_8:
				var next_fog := (WorldWeather.FOG_LEVELS.find(value.z) + 1) % WorldWeather.FOG_LEVELS.size()
				value = Vector3(0, value.y, WorldWeather.FOG_LEVELS[next_fog])
			KEY_9: value = Vector3.ZERO if value.x > 0 else Vector3(1, 0, 0)
			KEY_0:
				clock.weather_running = not clock.weather_running
				clock.running = clock.weather_running
				return
			KEY_BACKSPACE:
				var roof := main.get_node_or_null("NewRv/Chassis/RoofMiddle")
				if roof != null: roof.take_damage(100000)
				return
			_:
				super._unhandled_input(event)
				return
		clock.weather.set_weather(value, true)
		clock.apply_time()
		print("WEATHER PRESET ", value, " ", clock.weather.description())
		return
	super._unhandled_input(event)

func _process(delta: float) -> void:
	super._process(delta)
	if clock == null: return
	metrics_elapsed += delta
	frame_samples += 1
	frame_total += delta
	var rain := clock.get_node("WeatherRain") as WeatherRain
	rain.listener = player if player.camera.current else camera
	max_rays = maxi(max_rays, rain.rays_last_tick)
	if metrics_elapsed >= 5:
		print("WEATHER METRICS ", clock.weather.description(), " submitted_particles=", rain.visible_drops, " coverage_m=", WeatherRain.FAR_RADIUS * 2, " max_rays=", max_rays, " frame_ms=", snappedf(frame_total * 1000 / frame_samples, 0.01))
		metrics_elapsed = 0
		frame_total = 0
		frame_samples = 0
		max_rays = 0
