extends "res://world/test_world.gd"
## Production death entry points and main world; shortcuts/captures are test-only.
const OUTPUT := "res://docs/validation/player-death-integration/current-60hz/"
var observer: Camera3D
var status: Label
var replaying := false
var start := Transform3D.IDENTITY

func _enter_tree() -> void:
	set_meta("checkpoint_staging", true)
	super._enter_tree()
	$WorldGenerator.world_seed = 42
	$Player.position = Vector3(4, 4, 12)

func _ready() -> void:
	super._ready()
	if not await wait_for_play():
		get_tree().quit(1)
		return
	get_window().title = "ApocalypseRV - Player Death Integration"
	get_window().size = Vector2i(1280, 900)
	observer = Camera3D.new()
	add_child(observer)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(20, 145)
	status.add_theme_font_size_override("font_size", 19)
	canvas.add_child(status)
	status.text = "DEATH / production world / %d Hz\nF1 first person | F2 observer | F3 lethal hit | F4 replay | F5 seated death | Esc close" % Engine.physics_ticks_per_second
	$WorldClock.set_time(1, 10)
	$WorldClock.set_process(false)
	await seconds(1.0)
	start = $Player.global_transform
	_view(false)
	print("PLAYER_DEATH_READY")
	if "--replay" in OS.get_cmdline_user_args(): _replay()

func seconds(duration: float) -> void:
	for frame in ceili(duration * Engine.physics_ticks_per_second): await get_tree().physics_frame

func _input(event: InputEvent) -> void:
	if observer == null or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		get_tree().quit()
		return
	if replaying: return
	match event.keycode:
		KEY_F1: _view(false)
		KEY_F2: _view(true)
		KEY_F3: _kill()
		KEY_F4: _replay()
		KEY_F5:
			$NewRv/Chassis/DriverSeat.interact_hold($Player)
			_kill()

func _kill() -> void:
	$Player.damage_cooldown = 0
	$Player.take_damage(1000)

func _view(external: bool) -> void:
	if external:
		var target: Vector3 = $Player.global_position + Vector3.UP * .8
		if $Player.ragdoll_control.active: target = $Player.ragdoll_control.bodies["pelvis"].global_position
		observer.global_position = target + Vector3(2, 1.3, -2.2)
		observer.look_at(target)
		observer.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		$Player.camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func capture(label: String, external: bool) -> void:
	_view(external)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(OUTPUT + label + ".png")
	if error != OK: push_error("Screenshot failed: " + label)

func _replay() -> void:
	if replaying or $Player.is_player_dead: return
	replaying = true
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var results: Array = []
	for scenario in ["standing", "airborne", "driver"]:
		$Player.complete_world_transition(start)
		await seconds(.2)
		if scenario == "airborne":
			$Player.position.y += 1.8
			$Player.velocity = Vector3(1, -1, 0)
		elif scenario == "driver":
			$NewRv/Chassis/DriverSeat.interact_hold($Player)
		await capture(scenario + "_before", false)
		_kill()
		await seconds(.65)
		await capture(scenario + "_fall_first_person", false)
		await capture(scenario + "_fall_external", true)
		await seconds(.65)
		await capture(scenario + "_ground_first_person", false)
		await capture(scenario + "_ground_external", true)
		await seconds(1.1)
		await capture(scenario + "_recovered", false)
		var position_before: Vector3 = $Player.global_position
		Input.action_press("move_back")
		await seconds(.5)
		Input.action_release("move_back")
		results.append({"case": scenario, "alive": not $Player.is_player_dead, "physics_stopped": not $Player.ragdoll_control.active, "movement_m": $Player.global_position.distance_to(position_before)})
	var report := {"godot": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(), "physics_hz": Engine.physics_ticks_per_second, "cases": results}
	FileAccess.open(OUTPUT + "replay.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PLAYER_DEATH_REPLAY ", JSON.stringify(report))
	replaying = false
	if "--quit-replay" in OS.get_cmdline_user_args(): get_tree().quit()
