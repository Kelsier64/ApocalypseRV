extends "res://world/test_world.gd"
## Real main world and production Player. Only cameras/replay/capture are test code.
const OUTPUT := "res://docs/validation/player-model-integration/"
var observer: Camera3D
var status: Label
var replaying := false
var results: Dictionary = {}

func _enter_tree() -> void:
	set_meta("checkpoint_staging", true)
	super._enter_tree()
	$WorldGenerator.world_seed = 42
	$Player.position = Vector3(4, 4, 12)

func _ready() -> void:
	super._ready()
	if not await wait_for_play():
		push_error("Production world did not become ready")
		get_tree().quit(1)
		return
	get_window().title = "ApocalypseRV - Player Model Integration"
	get_window().size = Vector2i(1280, 900)
	observer = Camera3D.new()
	observer.far = 300
	add_child(observer)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(20, 145)
	status.add_theme_font_size_override("font_size", 19)
	canvas.add_child(status)
	status.text = "PLAYER MODEL / production world\nF1 first person | F2 look down | F3 observer | F4 replay | Esc close"
	# Keep ordinary weather/light materials; freeze a reproducible morning.
	$WorldClock.set_time(1, 10)
	$WorldClock.set_process(false)
	for frame in 120: await get_tree().physics_frame
	_view(2)
	print("PLAYER_MODEL_READY")
	if "--replay" in OS.get_cmdline_user_args(): _replay()

func _unhandled_key_input(event: InputEvent) -> void:
	if observer == null or replaying or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F1: _view(0)
		KEY_F2: _view(1)
		KEY_F3: _view(2)
		KEY_F4: _replay()
		KEY_ESCAPE: get_tree().quit()

func _view(mode: int) -> void:
	if mode < 2:
		$Player.camera.rotation = Vector3(deg_to_rad(-80 if mode == 1 else 0), 0, 0)
		$Player.camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		observer.global_position = $Player.to_global(Vector3(1.5, 1.8, -2.4))
		observer.look_at($Player.to_global(Vector3(0, 1.0, 0)))
		observer.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(OUTPUT + filename + ".png")
	if error != OK: push_error("Capture failed: " + filename)

func _replay() -> void:
	if replaying: return
	replaying = true
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_view(2)
	await _capture("observer")
	_view(0)
	await _capture("first_person_forward")
	_view(1)
	await _capture("first_person_down")
	var start: Vector3 = $Player.global_position
	Input.action_press("move_forward")
	for frame in 45: await get_tree().physics_frame
	Input.action_release("move_forward")
	results["walk_distance_m"] = start.distance_to($Player.global_position)
	await _capture("walking_down")
	Input.action_press("jump")
	for frame in 15: await get_tree().physics_frame
	Input.action_release("jump")
	results["jump_off_floor"] = not $Player.is_on_floor()
	await _capture("jump_down")
	for frame in 90: await get_tree().physics_frame
	# Existing inventory and seat ownership paths, no alternate controller.
	$Player.add_item("Scrap", false, "res://props/scrap.tscn")
	_view(0)
	await _capture("held_item")
	var seat := $NewRv/Chassis/DriverSeat
	seat.interact_hold($Player)
	results["seat_entered"] = $Player.seated_in == seat
	await _capture("seated")
	seat.exit_seat()
	results["seat_exited"] = $Player.seated_in == null and $Player.get_node("Visuals").is_visible_in_tree()
	_view(1)
	await _capture("seat_exit_down")
	_view(2)
	await _capture("seat_exit_observer")
	results["godot"] = Engine.get_version_info().string
	results["renderer"] = RenderingServer.get_current_rendering_method()
	results["physics_hz"] = Engine.physics_ticks_per_second
	var file := FileAccess.open(OUTPUT + "replay.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("PLAYER_MODEL_REPLAY ", JSON.stringify(results))
	replaying = false
	if "--quit-replay" in OS.get_cmdline_user_args(): get_tree().quit()
