extends SceneTree
## Isolated preference files; never write the user's settings or checkpoint.
const PATH := "res://.godot/test-logs/settings-regression/preferences.cfg"
const KEYS := ["window_mode", "vsync", "max_fps", "render_mode", "render_scale", "aa", "shadow_quality", "fog_quality", "retro", "brightness", "contrast", "saturation", "sensitivity", "invert_y", "walk_fov", "drive_fov", "master_volume"]
var failures: Array[String] = []
var settings: Node
var defaults: Dictionary = {}
var saves: Array[int] = []

class FogPreferences extends "res://core/game_settings.gd":
	# Deterministic renderer-capability seam: headless verifies Environment
	# state transitions, while native GPU output remains a separate check.
	var hardware_support := true
	func supports_volumetric_fog() -> bool:
		return hardware_support

class ClockWithPreferences extends WorldClock:
	var preferences: Node
	func _ready() -> void:
		game_settings = preferences
		super._ready()

func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value: failures.append(note)
func write_config(values: Dictionary) -> void:
	var file := ConfigFile.new()
	for section: String in values:
		for key: String in values[section]: file.set_value(section, key, values[section][key])
	check(file.save(PATH) == OK, "Fixture preferences save")
func snapshot() -> Dictionary:
	var result := {}
	for key: String in KEYS: result[key] = settings.get_setting(key)
	return result
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))
	write_config({})
	settings = load("res://core/game_settings.gd").new()
	settings.storage_path = PATH
	root.add_child(settings)
	settings.save_completed.connect(func(error: int): saves.append(error))
	defaults = snapshot()
	check(defaults.walk_fov == 75.0 and defaults.drive_fov == 80.0, "Default walking and driving FOV remain distinct")
	for retro: bool in [false, true]:
		write_config({"display": {"retro": retro}})
		check(settings.load_preferences(PATH) == OK, "Legacy display preferences load")
		check(settings.get_setting("render_mode") == (0 if retro else 1), "Legacy retro value migrates resolution mode")
		check(settings.get_setting("render_scale") == 1.0 and settings.get_setting("retro") == retro, "Legacy migration preserves native scale and independent color toggle")
	write_config({"display": {"render_mode": 1, "render_scale": 0.8, "retro": true}})
	settings.load_preferences(PATH)
	check(settings.get_setting("render_mode") == 1 and settings.get_setting("render_scale") == 0.8, "Explicit manual scale survives legacy color toggle")
	var invalid := {"display": {"window_mode": 3, "vsync": "false", "max_fps": -1, "render_mode": 3, "render_scale": NAN, "aa": 4, "shadow_quality": -1, "fog_quality": 4, "retro": "false", "brightness": INF, "contrast": 1.5, "saturation": -0.1}, "input": {"sensitivity": 0.0, "invert_y": 1, "walk_fov": 101, "drive_fov": "80"}, "audio": {"master_volume": INF}}
	write_config(invalid)
	settings.load_preferences(PATH)
	check(snapshot() == defaults, "Malformed, non-finite and out-of-range persisted fields each fall back to defaults")
	for key: String in ["render_scale", "brightness", "contrast", "saturation", "sensitivity", "walk_fov", "drive_fov", "master_volume"]:
		for bad: Variant in [NAN, INF, -INF, "1"]:
			var previous: Variant = settings.get_setting(key)
			check(not settings.set_setting(key, bad) and settings.get_setting(key) == previous, "Rejected %s write cannot mutate live value" % key)
	check(not settings.set_setting("unknown", 1), "Unknown preference is refused")
	settings.set_setting("brightness", 1.1)
	settings.set_setting("saturation", 0.7)
	settings.set_setting("retro", false)
	settings.set_setting("sensitivity", 1.5)
	settings.set_setting("master_volume", 0.4)
	var master := AudioServer.get_bus_index("Master")
	check(not AudioServer.is_bus_mute(master) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(master)), 0.4), "Master preference controls the actual audio bus gain")
	settings.set_setting("master_volume", 0.0)
	check(AudioServer.is_bus_mute(master), "Zero master volume mutes the actual audio bus")
	settings.set_setting("master_volume", 0.4)
	var independent := snapshot()
	for index in range(4):
		settings.apply_preset(index)
		check(settings.preset_index() == index, "Explicit quality preset selects source %d" % index)
		for key: String in KEYS:
			if key in ["render_mode", "render_scale", "aa", "shadow_quality", "fog_quality"]: continue
			check(settings.get_setting(key) == independent[key], "Quality preset leaves %s untouched" % key)
	settings.apply_preset(1)
	settings.set_setting("aa", 1)
	check(settings.preset_index() == 4, "Manual AA adjustment changes the selected Low preset to Custom")
	settings.set_setting("aa", 0)
	check(settings.preset_index() == 4, "Restoring AA to Low's exact value retains the manual Custom source")
	check(settings.flush() == OK and settings.load_preferences(PATH) == OK and settings.preset_index() == 4, "Custom source persists even when saved quality values match Low")
	settings.apply_preset(1)
	check(settings.preset_index() == 1, "Explicitly selecting Low again restores the Low source")
	settings.reset_category("display")
	check(settings.preset_index() == 0, "Display reset explicitly restores the Original quality source")
	settings.set_setting("render_scale", 0.83)
	check(settings.preset_index() == 4, "Editing quality retains a Custom source")
	settings.reset_category("input")
	check(settings.get_setting("sensitivity") == defaults.sensitivity and settings.get_setting("master_volume") == 0.4, "Input reset leaves audio and display alone")
	await test_viewports()
	await test_fog_switch()
	saves.clear()
	settings.set_setting("brightness", 0.9)
	settings.set_setting("brightness", 1.0)
	settings.set_setting("brightness", 1.2)
	check(saves.is_empty(), "Slider changes are debounced rather than writing synchronously")
	check(settings.flush() == OK and saves == [OK], "Explicit flush coalesces changes into one successful save notification")
	var expected := snapshot()
	settings.reset_category("display")
	settings.load_preferences(PATH)
	check(snapshot() == expected, "Saved settings reload independently from world checkpoint")
	saves.clear()
	settings.set_setting("contrast", 1.1)
	for frame in range(90): await process_frame
	check(saves == [OK], "Debounced edit eventually persists once")
	settings.storage_path = PATH + "/cannot-write.cfg"
	settings.set_setting("contrast", 0.9)
	var error: int = settings.flush()
	check(error != OK and settings.last_save_error == error and saves.back() == error, "Failed preference save returns and signals its actual error")
	settings.storage_path = PATH
	check(settings.flush() == OK, "Pending failed save can retry on a writable path")
	var old_mode: int = settings.get_setting("window_mode")
	settings.begin_window_preview(1 - old_mode)
	check(settings.preview_remaining() > 0.0, "Window preview starts confirmation countdown")
	settings.set_setting("brightness", 1.1)
	settings.flush()
	var persisted := ConfigFile.new()
	persisted.load(PATH)
	check(persisted.get_value("display", "window_mode") == old_mode, "Saving another preference during preview preserves only the confirmed window mode")
	settings.cancel_window_preview()
	check(settings.get_setting("window_mode") == old_mode, "Cancelled window preview restores confirmed preference")
	settings.window_preview_seconds = 0.0
	settings.begin_window_preview(1 - old_mode)
	await process_frame

	await process_frame
	check(settings.get_setting("window_mode") == old_mode and settings.preview_remaining() == 0.0, "Expired preview restores confirmed preference without user input")
	settings.window_preview_seconds = 15.0
	settings.begin_window_preview(1 - old_mode)
	settings.confirm_window_preview()
	persisted.load(PATH)
	check(persisted.get_value("display", "window_mode") == 1 - old_mode, "Confirming preview persists the new window preference")
	if DisplayServer.get_name() == "headless": print("NOTE: Preview preference state is tested; native window output, VSync and GPU visuals require display testing.")
	settings.queue_free()
	await process_frame
	# Restore process-wide rendering/audio limits from the real autoload.
	var live := root.get_node_or_null("GameSettings")
	if live:
		live.load_preferences()
	if failures.is_empty(): print("PASS: settings validation, migration, presets, viewport application and independent persistence")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func test_viewports() -> void:
	var outdoor := SubViewport.new()
	outdoor.size = Vector2i(1920, 1080)
	outdoor.positional_shadow_atlas_size = 1024
	root.add_child(outdoor)
	settings.register_viewport(outdoor, false)
	settings.set_setting("render_mode", 1)
	settings.set_setting("render_scale", 0.7)
	settings.set_setting("aa", 2)
	var indoor := SubViewport.new()
	indoor.size = Vector2i(1280, 720)
	root.add_child(indoor)
	settings.register_viewport(indoor, true)
	await process_frame
	check(is_equal_approx(outdoor.scaling_3d_scale, 0.7) and is_equal_approx(indoor.scaling_3d_scale, 0.7), "Manual scale reaches outdoor and newly created interior viewports")
	check(outdoor.msaa_3d == Viewport.MSAA_2X and indoor.msaa_3d == Viewport.MSAA_2X, "2x AA reaches every registered viewport")
	settings.set_setting("shadow_quality", 1)
	check(outdoor.positional_shadow_atlas_size == 2048 and indoor.positional_shadow_atlas_size == 2048, "Low shadow quality applies to all registered viewport atlases")
	settings.set_setting("shadow_quality", 0)
	check(outdoor.positional_shadow_atlas_size == 1024, "Original shadow quality restores each viewport's own captured atlas size")
	settings.set_setting("fog_quality", 0)
	check(not settings.volumetric_fog_enabled(), "Fog-off disables volume quality without requiring renderer support")
	settings.set_setting("retro", true)
	check(is_equal_approx(indoor.scaling_3d_scale, 0.7), "Retro color toggle cannot change manual indoor resolution")
	settings.set_setting("render_mode", 0)
	await process_frame
	check(is_equal_approx(outdoor.scaling_3d_scale, 0.5) and indoor.scaling_3d_scale == 1.0, "Legacy 540p scale applies outdoors and preserves native indoor resolution")
	outdoor.queue_free()
	indoor.queue_free()
	await process_frame

func test_fog_switch() -> void:
	var preferences := FogPreferences.new()
	preferences.storage_path = PATH + ".fog"
	root.add_child(preferences)
	preferences.set_setting("fog_quality", 0, false)
	var world := Node3D.new()
	root.add_child(world)
	var holder := WorldEnvironment.new()
	holder.name = "WorldEnvironment"
	holder.environment = Environment.new()
	world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	world.add_child(sun)
	var clock := ClockWithPreferences.new()
	clock.preferences = preferences
	clock.running = false
	clock.weather_running = false
	world.add_child(clock)
	clock.weather.set_weather(Vector3.ZERO, true)
	clock.apply_time()
	var environment := holder.environment
	check(not environment.volumetric_fog_enabled and environment.fog_enabled and environment.fog_depth_end == 380.0, "World created with fog quality Off starts with authored distance fog")
	var weather_state := clock.weather.capture()
	var time_state := clock.capture()
	var light_energy := sun.light_energy
	preferences.set_setting("fog_quality", 2, false)
	check(environment.volumetric_fog_enabled and is_equal_approx(environment.volumetric_fog_density, 0.0015), "Enabling volume quality on an existing clock enables the authored overcast density")
	check(environment.volumetric_fog_albedo.is_equal_approx(Color(0.28, 0.31, 0.30)) and environment.volumetric_fog_length == 160.0 and environment.volumetric_fog_detail_spread == 2.0, "A clock started in distance mode retains authored volume color, range and near-camera detail")
	check(environment.volumetric_fog_anisotropy == 0.0 and is_equal_approx(environment.volumetric_fog_ambient_inject, 0.08) and environment.volumetric_fog_temporal_reprojection_enabled and is_equal_approx(environment.volumetric_fog_temporal_reprojection_amount, 0.8), "Switching fog on uses authored scattering and temporal parameters rather than Environment defaults")
	check(clock.weather.capture() == weather_state and clock.capture() == time_state and sun.light_energy == light_energy, "Fog quality switch does not advance weather/time or change solar energy")
	clock.weather.set_weather(Vector3(0, 0, 2), true)
	clock.apply_time()
	check(environment.fog_enabled and environment.fog_depth_begin == 8.0 and environment.fog_depth_end == 38.0 and environment.volumetric_fog_density == 0.0, "Heavy weather fog retains its short distance-fog range and suppresses volumetric density")
	preferences.set_setting("fog_quality", 0, false)
	check(not environment.volumetric_fog_enabled and environment.fog_depth_end == 38.0, "Turning volume quality off cannot remove heavy weather distance fog")
	preferences.set_setting("fog_quality", 3, false)
	check(environment.fog_depth_end == 38.0 and environment.volumetric_fog_density == 0.0, "High volume quality also leaves heavy weather fog in distance mode")
	preferences.hardware_support = false
	clock.weather.set_weather(Vector3.ZERO, true)
	clock.apply_time()
	check(not environment.volumetric_fog_enabled and environment.fog_depth_end == 380.0, "Unsupported renderer retains distance fallback despite selected volume quality")
	world.queue_free()
	preferences.queue_free()
	await process_frame
