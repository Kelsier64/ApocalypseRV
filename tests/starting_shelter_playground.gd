extends "res://world/main_world.gd"
## Real wheel-powered departure; no vehicle transforms or velocities during replay.
var replay_running := false
var replay_started := false
var replay_time := 0.0
var route_index := 0
var route: Array[Vector3] = []
var replay_vehicle: Chassis
var overview: Camera3D
var status: Label
var auto_replay := false

func _ready() -> void:
	super._ready()
	_setup_replay.call_deferred()

func _setup_replay() -> void:
	if not await wait_for_play(): return
	replay_vehicle = get_node("NewRv/Chassis")
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	status = Label.new()
	status.position = Vector2(24, 110)
	status.add_theme_font_size_override("font_size", 22)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(status)
	status.text = "F2 drive | F3 exterior | F4 interior / player | F5 roadblock | F6 facade | F7 wall"
	overview = Camera3D.new()
	overview.fov = 82
	add_child(overview)
	_interior_camera()
	if "--art-daylight" in OS.get_cmdline_user_args(): get_node("WorldClock").set_time(1, 15.0)
	if "--inspect-roadblock" in OS.get_cmdline_user_args(): _roadblock_camera()
	if "--inspect-exterior" in OS.get_cmdline_user_args(): _exterior_camera()
	if "--inspect-facade" in OS.get_cmdline_user_args(): _facade_camera()
	auto_replay = "--replay" in OS.get_cmdline_user_args()
	if auto_replay:
		await get_tree().create_timer(3.0).timeout
		_start_replay()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F2 or event.keycode == KEY_F2: _start_replay()
		if event.physical_keycode == KEY_F3 or event.keycode == KEY_F3: _exterior_camera()
		if event.physical_keycode == KEY_F5 or event.keycode == KEY_F5: _roadblock_camera()
		if event.physical_keycode == KEY_F6 or event.keycode == KEY_F6: _facade_camera()
		if event.physical_keycode == KEY_F7 or event.keycode == KEY_F7: _wall_camera()
		if (event.physical_keycode == KEY_F4 or event.keycode == KEY_F4) and is_instance_valid(overview):
			if overview.current: get_node("Player").camera.make_current()
			else: _interior_camera()

func _roadblock_camera() -> void:
	if not is_instance_valid(overview): return
	overview.global_position = Vector3(-18, 8, -5)
	overview.look_at(Vector3(0, 2, 20))
	overview.make_current()

func _exterior_camera() -> void:
	if not is_instance_valid(overview): return
	overview.global_position = Vector3(-10, 16, -90)
	overview.look_at(Vector3(56, 6, -45))
	overview.make_current()

func _interior_camera() -> void:
	var shelter: Node3D = get_node("StartRun").shelter
	overview.global_position = shelter.to_global(Vector3(8.2, 4.7, -11.5))
	overview.look_at(shelter.to_global(Vector3(0, 2, 6)))
	overview.make_current()

func _facade_camera() -> void:
	if not is_instance_valid(overview): return
	var shelter: Node3D = get_node("StartRun").shelter
	overview.global_position = shelter.to_global(Vector3(-23, 2.4, 28))
	overview.look_at(shelter.to_global(Vector3(-7, 4.2, 12.5)))
	overview.make_current()

func _wall_camera() -> void:
	if not is_instance_valid(overview): return
	var shelter: Node3D = get_node("StartRun").shelter
	overview.global_position = shelter.to_global(Vector3(-6, 1.8, 6))
	overview.look_at(shelter.to_global(Vector3(-9.9, 2.6, -2)))
	overview.make_current()

func _start_replay() -> void:
	if replay_started or not is_instance_valid(replay_vehicle): return
	replay_started = true
	var run: Node = get_node("StartRun")
	var player: Node3D = get_node("Player")
	run.shelter.get_node("GarageButton").interact(player)
	status.text = "OPENING: production door, physical leaves remain active"
	while run.phase == "opening": await get_tree().physics_frame
	if run.phase != "started":
		_finish(false, "garage did not open")
		return
	# Sitting is setup; every subsequent vehicle movement uses wheel controls.
	replay_vehicle.get_node("DriverSeat").interact_hold(player)
	if player.seated_in == null:
		_finish(false, "driver could not enter seat")
		return
	replay_vehicle.allow_test_controls = true
	replay_vehicle.set_engine_running(true)
	replay_vehicle.set_gear(1)
	replay_vehicle.set_handbrake(false)
	var site: Dictionary = run.shelter_site
	# Road-relative points create a broad left turn from the east-side garage.
	for point in [Vector3(24, 0, 0), Vector3(17, 0, 0), Vector3(10, 0, -2), Vector3(4, 0, -9), Vector3(0, 0, -22), Vector3(0, 0, -65)]:
		route.append(site.road * point)
	_interior_camera()
	replay_running = true
	print("SHELTER_DRIVE_BEGIN: production wheels, normal fuel, no repositioning")

func _physics_process(delta: float) -> void:
	if not replay_running: return
	replay_time += delta
	var target := route[route_index]
	var distance := Vector2(target.x - replay_vehicle.global_position.x, target.z - replay_vehicle.global_position.z).length()
	if distance < 4.0 and route_index < route.size() - 1:
		route_index += 1
		target = route[route_index]
	var local := replay_vehicle.to_local(target)
	var angle := atan2(-local.x, -local.z)
	var speed := replay_vehicle.linear_velocity.length()
	var steering := clampf(angle * 1.5 / replay_vehicle.max_steering, -1.0, 1.0)
	var desired_speed := 3.0 if route_index < 5 else 4.0
	replay_vehicle.control_override = {"throttle": clampf((desired_speed - speed) * 0.6, 0.0, 0.65), "brake": clampf((speed - desired_speed) * 0.8, 0.0, 1.0), "steering": steering}
	var run: Node = get_node("StartRun")
	if replay_vehicle.global_position.x < 29.0:
		overview.global_position = replay_vehicle.global_position + Vector3(12, 9, 14)
		overview.look_at(replay_vehicle.global_position + Vector3(0, 1, -4))
	status.text = "WHEEL DRIVE  %.1f m/s | route %d/6 | gate %s" % [speed, route_index + 1, run.phase]
	if replay_vehicle.global_position.y < -2 or replay_vehicle.global_basis.y.y < 0.65:
		_finish(false, "lost ground support or rolled over")
	elif replay_time > 100.0:
		_finish(false, "departure timed out at %s" % replay_vehicle.global_position)
	elif route_index == route.size() - 1 and distance < 5:
		_finish(run.phase == "sealed", "exited, turned onto forward highway and garage " + run.phase)

func _finish(ok: bool, detail: String) -> void:
	replay_running = false
	if is_instance_valid(replay_vehicle):
		replay_vehicle.control_override = {"brake": 1.0}
		replay_vehicle.set_handbrake(true)
	var message := "%s: SHELTER_WHEEL_DEPARTURE %s (%.1fs)" % ["PASS" if ok else "FAIL", detail, replay_time]
	print(message)
	if status != null: status.text = message
	if not ok: push_error(message)
	if auto_replay and "--keep-open" not in OS.get_cmdline_user_args():
		await get_tree().create_timer(3.0).timeout
		get_tree().quit(0 if ok else 1)
