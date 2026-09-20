extends "res://tests/day_night_playground.gd"
const PRESETS := [Vector3.ZERO, Vector3(0, 1, 0), Vector3(0, 2, 0), Vector3(0, 0, 1), Vector3(0, 0, 2), Vector3(1, 0, 0), Vector3(0, 2, 2)]
var preset := 0
var metrics_elapsed := 0.0
var frame_samples := 0
var frame_total := 0.0
var max_rays := 0

func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - Weather Validation"
	clock.weather_running = false
	clock.set_time(1, 12)
	stage = 0
	_view()
	time_controls.text += "\n6 weather presets | 7 rain | 8 fog | 9 clear/overcast | 0 auto weather | Backspace destroy roof"
	# Audio must follow the observer in this detached-camera validation scene.
	clock.get_node("WeatherRain").listener = camera
	if "--heavy-rain" in OS.get_cmdline_user_args():
		preset = 2
		clock.weather.set_weather(PRESETS[preset], true)
		clock.apply_time()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var value := clock.weather.target
		match event.keycode:
			KEY_6:
				preset = (preset + 1) % PRESETS.size()
				value = PRESETS[preset]
			KEY_7: value = Vector3(0, fmod(value.y + 1, 3), value.z)
			KEY_8: value = Vector3(0, value.y, fmod(value.z + 1, 3))
			KEY_9: value = Vector3.ZERO if value.x > 0 else Vector3(1, 0, 0)
			KEY_0:
				clock.weather_running = not clock.weather_running
				clock.running = clock.weather_running
				return
			KEY_BACKSPACE:
				var roof := main.get_node_or_null("NewRv/Chassis/Ceiling")
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
