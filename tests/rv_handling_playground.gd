extends Node3D

const Fixture := preload("res://tests/support/rv_handling_fixture.gd")
const JACK := preload("res://props/recovery_jack.tscn")

var station: Node3D
var vehicle: Chassis
var player: CharacterBody3D
var jack: RecoveryJack
var hud: Label
var station_title := ""
var changing := false

func _ready() -> void:
	get_window().title = "ApocalypseRV - Handling and Recovery"
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var setting := WorldEnvironment.new()
	setting.environment = Environment.new()
	setting.environment.background_mode = Environment.BG_COLOR
	setting.environment.background_color = Color("#a3b9ca")
	setting.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	setting.environment.ambient_light_color = Color("#c3c7ce")
	setting.environment.ambient_light_energy = 0.6
	add_child(setting)
	var canvas := CanvasLayer.new()
	canvas.layer = 6
	add_child(canvas)
	hud = Label.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.position.y = 18
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_theme_constant_override("outline_size", 5)
	canvas.add_child(hud)
	var arguments := OS.get_cmdline_user_args()
	var mode := 2
	for argument in arguments:
		if argument.begins_with("--station="): mode = clampi(int(argument.get_slice("=", 1)), 2, 6)
	await _setup(mode)
	if "--capture" in arguments: await _capture_jack()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode < KEY_F2 or event.physical_keycode > KEY_F6: return
	get_viewport().set_input_as_handled()
	_setup(event.physical_keycode - KEY_F2 + 2)

func _setup(mode: int) -> void:
	if changing: return
	changing = true
	if is_instance_valid(station):
		station.queue_free()
		await get_tree().process_frame
	station = Node3D.new()
	add_child(station)
	var tilt := 1.08 if mode == 3 else 0.0
	var surface := Fixture.ground(station, tilt)
	RoadsideKit.part(surface, Vector3(220.0, 1.0, 220.0), Vector3.DOWN * 0.5, Color("#45494b"))
	var spawn := Vector3(0, 1.5, 23)
	var roll := tilt
	match mode:
		2:
			station_title = "Asphalt slalom and circle | Use W/A/S/D, Space for the handbrake"
			for i in 8:
				RoadsideKit.part(station, Vector3(0.48, 0.9, 0.48), Vector3(0, 0.45, 12 - i * 9), Color("#db7236"), true, "cone")
			for i in 20:
				var angle := TAU * i / 20.0
				var point := Vector3(34 + cos(angle) * 18, 0.012, -18 + sin(angle) * 18)
				RoadsideKit.part(station, Vector3(1.0, 0.02, 1.0), point, Color("#d2d0aa"))
		3:
			station_title = "Steep cross-slope | Press E to try an emergency exit after settling"
			spawn.y = 2.15
		4:
			station_title = "Curb trip | The RV starts in a sideways slide"
			RoadsideKit.part(station, Vector3(0.7, 0.75, 60), Vector3(-4.3, 0.37, 0), Color("#9a9284"), true)
		5:
			station_title = "Wall crash | 12 m/s approach, stay seated or press E to stand"
			RoadsideKit.part(station, Vector3(15, 4.0, 1.0), Vector3(0, 2.0, -4), Color("#9d7760"), true)
		6:
			station_title = "Recovery | Tap E to pick up the jack, G to drop, hold E to lift"
			spawn = Vector3(0, 2.85, 0)
			roll = PI
	vehicle = Fixture.vehicle(station, spawn, roll)
	vehicle.unlimited_fuel = true
	player = Fixture.player(station, Vector3(5.5, 0.1, 0.9) if mode == 6 else spawn + Vector3(4.0, 0, 0))
	if mode == 6:
		jack = JACK.instantiate()
		jack.position = Vector3(3.3, 0.025, 0)
		station.add_child(jack)
		player.rotation.y = PI / 2.0
	for i in 70: await get_tree().physics_frame
	if mode != 6:
		var seat := vehicle.get_node("DriverSeat")
		seat.interact_hold(player)
		vehicle.set_engine_running(true)
		if mode in [4, 5]:
			vehicle.set_handbrake(false)
			vehicle.set_gear(0)
			vehicle.linear_velocity = Vector3(-18.0, 0.0, -7.0) if mode == 4 else Vector3.FORWARD * 12.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	changing = false

func _process(_delta: float) -> void:
	if changing or not is_instance_valid(vehicle): return
	var state: String = ["Upright", "On its side", "Inverted"][vehicle.rollover_state()]
	hud.text = "%s\nF2 Slalom  F3 Slope  F4 Curb  F5 Wall  F6 Recovery\n%s  |  %.0f km/h  |  %.0f HP" % [station_title, state, vehicle.road_speed() * 3.6, player.current_player_health]

func _capture_jack() -> void:
	if not is_instance_valid(jack): await _setup(6)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = jack.global_position + Vector3(2.35, 1.75, 1.75)
	camera.look_at(jack.global_position + Vector3.UP * 0.16)
	camera.current = true
	camera.cull_mask &= ~PlayerModelVisual.LOCAL_VIEW_LAYER
	camera.fov = 49.0
	hud.hide()
	for i in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://.godot/recovery-jack-playground.png"
	var result := get_viewport().get_texture().get_image().save_png(path)
	if result == OK: print("CAPTURE: ", ProjectSettings.globalize_path(path))
	get_tree().quit(result)
