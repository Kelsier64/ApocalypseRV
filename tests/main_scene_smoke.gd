extends SceneTree
## Production scene, terrain, navigation and player must all become usable.
var settings: Node
var previous_storage_path: String
var previous_dirty: bool
var previous_save_delay: float
var previous_save_error: Error

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	settings = root.get_node("GameSettings")
	previous_storage_path = settings.storage_path
	previous_dirty = settings._dirty
	previous_save_delay = settings._save_delay
	previous_save_error = settings.last_save_error
	var isolated_path := "res://.godot/test-logs/main-smoke/preferences.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolated_path.get_base_dir()))
	settings.storage_path = isolated_path
	var world: Node3D = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	world.get_node("WorldGenerator").world_seed = 42
	root.add_child(world)
	current_scene = world
	var player: CharacterBody3D = world.get_node("Player")
	var menu: CanvasLayer = player.get_node("SettingsMenu")
	if await world.wait_for_play(0):
		push_error("FAIL: world reported ready before navigation synchronization")
		_finish(world, 1)
		return
	_escape()
	if player.settings_open or menu.visible or player.can_open_settings():
		push_error("FAIL: production settings opened before play readiness")
		_finish(world, 1)
		return
	if not await world.wait_for_play(60000):
		push_error("FAIL: world.ready_for_play timed out")
		_finish(world, 1)
		return
	if not await _tutorial_visibility_ready(world):
		_finish(world, 1)
		return
	_escape()
	await process_frame
	if not player.settings_open or not menu.visible or paused or root.gui_get_focus_owner() == null:
		push_error("FAIL: production Escape did not open focused settings without pausing")
		_finish(world, 1)
		return
	_escape()
	await process_frame
	if player.settings_open or menu.visible:
		push_error("FAIL: production Escape did not close settings")
		_finish(world, 1)
		return
	var before := player.global_position
	Input.action_press("move_forward")
	for i in range(30): await physics_frame
	Input.action_release("move_forward")
	var travelled := Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	if not player.global_transform.is_finite() or travelled < 0.1:
		push_error("FAIL: ready player cannot move")
		_finish(world, 1)
		return
	print("PASS: WORLD_READY_FOR_PLAY, frozen tutorial visibility, production Escape settings routing and player movement")
	_finish(world, 0)

func _tutorial_visibility_ready(world: Node3D) -> bool:
	var clock: WorldClock = world.get_node("WorldClock")
	var generator := world.get_node("WorldGenerator")
	var clock_before := clock.capture()
	var weather_before := clock.weather.capture()
	var deadline := Time.get_ticks_msec() + 20000
	for frame in range(720):
		if clock.running or clock.weather_running or clock.capture() != clock_before or clock.weather.capture() != weather_before:
			push_error("FAIL: tutorial visibility recovery advanced frozen time or weather")
			return false
		var camera := world.get_viewport().get_camera_3d()
		var clearance: float = generator.completed_scenery_clearance(camera.global_position)
		var weather_cap: float = clock.atmosphere.mist(clock.effective_visual_weather()).depth_end
		var expected := minf(weather_cap, clampf(clearance - clock.atmosphere.stream_margin, 1.0, clock.atmosphere.landscape_end))
		if expected > 1.0 and clock.environment.fog_depth_end >= expected - 0.5:
			return true
		if Time.get_ticks_msec() >= deadline: break
		await process_frame
	push_error("FAIL: ready tutorial retained near streaming fog instead of recovering completed scenery visibility")
	return false

func _escape() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)

func _finish(world: Node, result: int) -> void:
	world.free()
	# The menu's exit flush still targets the fixture. Restore pending state only
	# after all production nodes have exited, so the smoke never saves user data.
	settings.storage_path = previous_storage_path
	settings._dirty = previous_dirty
	settings._save_delay = previous_save_delay
	settings.last_save_error = previous_save_error
	quit(result)
