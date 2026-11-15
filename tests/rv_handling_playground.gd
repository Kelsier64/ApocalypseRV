extends Node3D

const Fixture := preload("res://tests/support/rv_handling_fixture.gd")
const JACK := preload("res://props/recovery_jack.tscn")
const STATIONS := ["Slalom", "Cross-slope", "Curb trip", "Wall crash", "Recovery"]
const TIPS := [
	"WASD drive, R/T shift, Space handbrake. Follow the cones or turn right into the circle.",
	"Start from the slope. Switch to chase view to watch the wheels lift.",
	"Start a sideways slide into the curb. Check the tilt and tire damage afterward.",
	"Choose a seated or standing occupant, then start the 12 m/s approach.",
	"Tap E to pick up the jack. Aim at the RV and hold E to lift. F9 moves you into range.",
]

var station: Node3D
var vehicle: Chassis
var player: CharacterBody3D
var jack: RecoveryJack
var jack_id := ""
var chase_camera: Camera3D
var hud: Label
var menu_shade: ColorRect
var menu: PanelContainer
var station_buttons: Array[Button] = []
var start_button: Button
var occupant_button: CheckButton
var jack_button: Button
var menu_open := false
var changing := false
var active_mode := 2
var awaiting_start := false
var standing := false
var chase := false
var peak_speed := 0.0
var front_health := 0.0
var tire_health := 0.0
var help_text := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	var screen := Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(screen)
	hud = Label.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud.anchor_left = 0.15
	hud.anchor_right = 0.85
	hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.position.y = 18
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_constant_override("outline_size", 5)
	screen.add_child(hud)
	_build_menu(screen)
	UILayout.attach(canvas, screen)
	var arguments := OS.get_cmdline_user_args()
	var mode := 2
	for argument in arguments:
		if argument.begins_with("--station="): mode = clampi(int(argument.get_slice("=", 1)), 2, 6)
	if "--capture" in arguments: sun.look_at_from_position(Vector3(5, 7, 5), Vector3.ZERO)
	await _setup(mode)
	if "--capture" in arguments:
		await _capture_jack()
	elif DisplayServer.get_name() != "headless" and not "--play" in arguments:
		_set_menu(true)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if changing: return
	var key: Key = event.physical_keycode if event.physical_keycode else event.keycode
	if (key == KEY_TAB or (key == KEY_ESCAPE and menu_open)) and not player.settings_open and not player.in_ui_mode:
		get_viewport().set_input_as_handled()
		_set_menu(not menu_open)
		return
	if key < KEY_F2 or key > KEY_F9:
		if not menu_open and key in [KEY_ENTER, KEY_KP_ENTER] and awaiting_start:
			get_viewport().set_input_as_handled()
			_start_run()
		return
	get_viewport().set_input_as_handled()
	match key:
		KEY_F7: _setup(active_mode)
		KEY_F8: _toggle_camera()
		KEY_F9: _stage_jack()
		_: _setup(key - KEY_F2 + 2)

func _build_menu(screen: Control) -> void:
	menu_shade = ColorRect.new()
	menu_shade.color = Color(0.02, 0.03, 0.04, 0.48)
	menu_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(menu_shade)
	var row := CenterContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(row)
	menu = PanelContainer.new()
	row.add_child(menu)
	var pad := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + edge, 18)
	menu.add_child(pad)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 8)
	pad.add_child(contents)
	var title := Label.new()
	title.text = "RV handling and recovery"
	title.add_theme_font_size_override("font_size", 24)
	contents.add_child(title)
	for i in STATIONS.size():
		var button := Button.new()
		button.text = "F%d   %s" % [i + 2, STATIONS[i]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 32.0
		button.toggle_mode = true
		button.pressed.connect(_setup.bind(i + 2))
		contents.add_child(button)
		station_buttons.append(button)
	occupant_button = CheckButton.new()
	occupant_button.text = "Standing occupant"
	occupant_button.toggled.connect(_select_occupant)
	contents.add_child(occupant_button)
	var actions := HBoxContainer.new()
	contents.add_child(actions)
	var retry := Button.new()
	retry.text = "F7  Retry"
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry.pressed.connect(func() -> void: _setup(active_mode))
	actions.add_child(retry)
	var camera := Button.new()
	camera.text = "F8  Camera"
	camera.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera.pressed.connect(_toggle_camera)
	actions.add_child(camera)
	jack_button = Button.new()
	jack_button.text = "F9  Position for lift"
	jack_button.pressed.connect(_stage_jack)
	contents.add_child(jack_button)
	start_button = Button.new()
	start_button.custom_minimum_size.y = 38.0
	start_button.pressed.connect(_continue_from_menu)
	contents.add_child(start_button)
	menu.hide()
	menu_shade.hide()

func _set_menu(open: bool) -> void:
	var was_open := menu_open
	menu_open = open
	menu.visible = open
	menu_shade.visible = open
	get_tree().paused = open and not changing
	if was_open and not open: player._capture_settings_release_latch()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	_refresh_menu()
	if open: start_button.grab_focus()

func _refresh_menu() -> void:
	for i in station_buttons.size():
		station_buttons[i].set_pressed_no_signal(i + 2 == active_mode)
		station_buttons[i].disabled = changing
	occupant_button.visible = active_mode == 5
	occupant_button.disabled = changing or not awaiting_start
	occupant_button.set_pressed_no_signal(standing)
	jack_button.visible = active_mode == 6
	jack_button.disabled = changing
	start_button.disabled = changing
	start_button.text = "Loading…" if changing else ("Start run" if awaiting_start else "Continue")

func _continue_from_menu() -> void:
	_set_menu(false)
	if awaiting_start: _start_run()

func _setup(mode: int) -> void:
	if changing: return
	if is_instance_valid(player): player.close_settings()
	changing = true
	active_mode = mode
	get_window().title = "ApocalypseRV - Hydraulic Recovery Jack" if mode == 6 else "ApocalypseRV - Handling and Recovery"
	awaiting_start = mode in [3, 4, 5]
	chase = false
	help_text = ""
	peak_speed = 0.0
	get_tree().paused = false
	_refresh_menu()
	hud.text = "Loading %s…" % STATIONS[mode - 2]
	if is_instance_valid(station):
		station.queue_free()
		await get_tree().process_frame
	station = Node3D.new()
	station.process_mode = Node.PROCESS_MODE_PAUSABLE
	station.set_meta("entity_domain", true)
	add_child(station)
	var tilt := 1.08 if mode == 3 else 0.0
	var surface := Fixture.ground(station, tilt)
	RoadsideKit.part(surface, Vector3(220.0, 1.0, 220.0), Vector3.DOWN * 0.5, Color("#45494b"))
	var spawn := Vector3(0, 1.5, 23)
	var roll := tilt
	match mode:
		2:
			for i in 8:
				RoadsideKit.part(station, Vector3(0.48, 0.9, 0.48), Vector3(0, 0.45, 12 - i * 9), Color("#db7236"), true, "cone")
			for i in 20:
				var angle := TAU * i / 20.0
				var point := Vector3(34 + cos(angle) * 18, 0.012, -18 + sin(angle) * 18)
				RoadsideKit.part(station, Vector3(1.0, 0.02, 1.0), point, Color("#d2d0aa"))
		3:
			spawn.y = 2.15
		4:
			RoadsideKit.part(station, Vector3(0.7, 0.75, 60), Vector3(-4.3, 0.37, 0), Color("#d9ab71"), true)
		5:
			RoadsideKit.part(station, Vector3(15, 4.0, 1.0), Vector3(0, 2.0, -4), Color("#9d7760"), true)
		6:
			spawn = Vector3(0, 2.9, 0)
			roll = PI
	vehicle = Fixture.vehicle(station, spawn, roll)
	vehicle.freeze = mode == 3
	vehicle.unlimited_fuel = true
	var walk_spawn := Vector3(4.0, 0.1, 0.0) if mode == 6 else spawn + Vector3(4.0, 0, 0)
	if mode == 3: walk_spawn = Vector3(0.0, 3.5, spawn.z + 9.0)
	player = Fixture.player(station, walk_spawn)
	chase_camera = Camera3D.new()
	station.add_child(chase_camera)
	chase_camera.fov = 65.0
	chase_camera.cull_mask &= ~PlayerModelVisual.LOCAL_VIEW_LAYER
	if mode == 6:
		jack = JACK.instantiate()
		jack.position = Vector3(3.3, 0.025, 0)
		jack.freeze = true
		station.add_child(jack)
		jack_id = jack.persistent_id
	for i in ceili(1.5 * Engine.physics_ticks_per_second): await get_tree().physics_frame
	if mode == 6:
		_aim_at_jack()
	else:
		_place_occupant()
		if mode in [3, 4] or (mode == 5 and standing):
			chase = true
			_update_chase(1.0)
			chase_camera.make_current()
		vehicle.set_engine_running(true)
	front_health = _front_health()
	tire_health = _lowest_tire()
	changing = false
	_set_menu(menu_open)

func _place_occupant() -> void:
	var seat := vehicle.get_node("DriverSeat")
	if active_mode == 5 and standing:
		seat.exit_seat()
		var point := vehicle.to_global(Vector3(0.15, 0.61, -1.3))
		player.global_transform = Transform3D(Basis(Vector3.UP, vehicle.global_rotation.y), point)
		player.camera.rotation = Vector3.ZERO
		player.velocity = Vector3.ZERO
		player.rv_support.clear()
		player.camera.make_current()
	else:
		seat.interact_hold(player)

func _select_occupant(value: bool) -> void:
	standing = value
	_setup(5)

func _start_run() -> void:
	if changing or not awaiting_start: return
	awaiting_start = false
	if active_mode == 3:
		vehicle.freeze = false
		return
	vehicle.set_handbrake(false)
	vehicle.set_gear(0)
	vehicle.linear_velocity = Vector3(-18.0, 0.0, -7.0) if active_mode == 4 else Vector3.FORWARD * 12.0

func _toggle_camera() -> void:
	if changing: return
	chase = not chase
	if chase:
		_update_chase(1.0)
		chase_camera.make_current()
	else:
		var seat := vehicle.get_node("DriverSeat")
		var player_camera: Camera3D = seat.seat_camera if player.seated_in == seat else player.camera
		player_camera.make_current()

func _update_chase(delta: float) -> void:
	var forward := vehicle.global_basis.z.slide(Vector3.UP).normalized()
	if forward.is_zero_approx(): forward = Vector3.BACK
	var side := Vector3.UP.cross(forward)
	var side_distance := -6.0 if active_mode == 3 else 6.0
	var back := forward * 11.0 + side * side_distance + Vector3.UP * 5.0
	var target := vehicle.global_position + Vector3.UP
	chase_camera.global_position = chase_camera.global_position.lerp(target + back, 1.0 - exp(-delta * 10.0))
	chase_camera.look_at(target)

func _stage_jack() -> void:
	if changing or active_mode != 6 or player.is_player_dead: return
	if not is_instance_valid(jack):
		for item in get_tree().get_nodes_in_group(Groups.ITEMS):
			if item is RecoveryJack and not item.presentation_only and item.persistent_id == jack_id:
				jack = item
				break
	var held: Dictionary = player.inventory.active_item()
	var has_jack: bool = held.get("state", {}).get("id") == jack_id
	if is_instance_valid(jack) and jack.is_lifting():
		help_text = "Wait for the current lift to finish."
		return
	if not is_instance_valid(jack) and not has_jack:
		help_text = "Select the jack in the hotbar, or press F7 to retry."
		return
	if vehicle.rollover_state() == Chassis.Rollover.UPRIGHT:
		help_text = "RV recovered. F7 resets this station."
		return
	if vehicle.linear_velocity.length() > RecoveryJack.MAX_START_SPEED or vehicle.angular_velocity.length() > RecoveryJack.MAX_START_SPIN:
		help_text = "Wait for the RV to stop."
		return
	var forward := vehicle.global_basis.z.slide(Vector3.UP).normalized()
	var side := Vector3.UP.cross(forward)
	if vehicle.rollover_state() == Chassis.Rollover.SIDE:
		side *= signf(vehicle.global_basis.y.cross(Vector3.UP).dot(forward))
	var point := vehicle.global_position.slide(Vector3.UP) + side * 3.0
	var capsule: CapsuleShape3D = player.standing_collision_shape
	var foot_height: float = player.standing_collision_transform.origin.y - capsule.height * 0.5
	player.global_position = point + side * (0.9 if has_jack else 1.35) - Vector3.UP * foot_height
	player.velocity = Vector3.ZERO
	if has_jack:
		_aim_at(vehicle.global_position + Vector3.UP * 0.3)
		help_text = "Hold E to deploy the jack."
	else:
		jack.freeze = true
		jack.global_position = point + Vector3.UP * 0.025
		jack.linear_velocity = Vector3.ZERO
		jack.angular_velocity = Vector3.ZERO
		jack.reset_physics_interpolation()
		_aim_at_jack()
		help_text = "Tap E to pick up the jack, or hold E to lift from the ground."
	player.reset_physics_interpolation()
	chase = false
	player.camera.make_current()

func _aim_at_jack() -> void:
	_aim_at(jack.to_global(Vector3(0.0, 0.11, 0.0)))

func _aim_at(point: Vector3) -> void:
	var facing := point - player.global_position
	player.rotation.y = atan2(-facing.x, -facing.z)
	var aim: Vector3 = point - player.camera.global_position
	player.camera.rotation = Vector3(atan2(aim.y, aim.slide(Vector3.UP).length()), 0.0, 0.0)

func _front_health() -> float:
	var slots := vehicle.get_node("StructureSlots") as RVStructureSlots
	var front := slots.panel("front")
	return front.current_health if front else 0.0

func _lowest_tire() -> float:
	return float(vehicle.wheel_health.min())

func _process(delta: float) -> void:
	if changing or not is_instance_valid(vehicle): return
	if chase and not menu_open:
		if not chase_camera.current: chase_camera.make_current()
		_update_chase(delta)
	var state: String = ["Upright", "On its side", "Inverted"][vehicle.rollover_state()]
	var speed := vehicle.road_speed() * 3.6
	peak_speed = maxf(peak_speed, speed)
	var instruction: String = TIPS[active_mode - 2]
	if awaiting_start: instruction = "Ready. Press Enter to start. " + instruction
	if active_mode == 6 and not help_text.is_empty(): instruction = help_text
	var status := "%s  |  %.0f km/h  |  %.0f HP" % [state, speed, player.current_player_health]
	if active_mode in [4, 5]:
		status += "  |  Peak %.0f km/h  |  Front −%.0f  |  Tire −%.0f" % [peak_speed, front_health - _front_health(), tire_health - _lowest_tire()]
	hud.text = "F%d %s  ·  %s\n%s\nTab Stations  ·  F7 Retry  ·  F8 Camera%s" % [
		active_mode, STATIONS[active_mode - 2], status, instruction, "  ·  F9 Position for lift" if active_mode == 6 else ""
	]

func _capture_jack() -> void:
	if not is_instance_valid(jack): await _setup(6)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.cull_mask &= ~PlayerModelVisual.LOCAL_VIEW_LAYER
	camera.fov = 44.0
	hud.hide()
	if not HUDVisibility.hud_hidden: HUDVisibility.toggle(get_tree())
	camera.global_position = jack.global_position + Vector3(1.04, 1.1, 1.15)
	camera.look_at(jack.global_position + Vector3.UP * 0.1)
	for i in 12: await get_tree().process_frame
	var result := await _save_capture("recovery-jack-folded")
	if result != OK:
		get_tree().quit(result)
		return
	jack.pickup(player)
	var deployment := RecoveryJack.deploy_from_inventory(player, vehicle)
	var deployed_jack := deployment.get("jack") as RecoveryJack
	if deployed_jack == null:
		push_error(deployment.message)
		get_tree().quit(1)
		return
	for i in 114: await get_tree().physics_frame
	station.process_mode = Node.PROCESS_MODE_DISABLED
	camera.global_position = deployed_jack.model.global_position + Vector3(2.2, 1.35, 2.75)
	camera.look_at(deployed_jack.model.global_position.lerp(deployed_jack.saddle.global_position, 0.5))
	result = await _save_capture("recovery-jack-deployed")
	if result != OK:
		get_tree().quit(result)
		return
	var surface := deployed_jack.load_surface()
	camera.fov = 37.0
	camera.global_position = surface.origin - surface.basis.y * 0.76 + surface.basis.x * 0.63 + Vector3.UP * 0.26
	camera.look_at(surface.origin - Vector3.UP * 0.10)
	get_tree().quit(await _save_capture("recovery-jack-contact"))

func _save_capture(name: String) -> Error:
	await RenderingServer.frame_post_draw
	var path := "res://.godot/%s.png" % name
	var result := get_viewport().get_texture().get_image().save_png(path)
	if result == OK: print("CAPTURE: ", ProjectSettings.globalize_path(path))
	return result
