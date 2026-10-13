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
var review_mode := false

static func requests_review(args: PackedStringArray) -> bool:
	for arg in ["--review", "--replay", "--art-daylight", "--inspect-exterior", "--inspect-facade", "--inspect-gate", "--inspect-lamp"]:
		if arg in args: return true
	return false

func _ready() -> void:
	review_mode = requests_review(OS.get_cmdline_user_args())
	super._ready()
	if review_mode:
		# Review runs bypass the lesson only when explicitly requested.
		get_node("StartRun/Tutorial").restore({})
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
	status.text = "STAGE 1 REVIEW | F2 drive | F3 exterior | F4 first bay / player | F6 facade | F7 service bay | F8 gate | F9 lamp"
	overview = Camera3D.new()
	overview.fov = 82
	add_child(overview)
	_interior_camera()
	if "--art-daylight" in OS.get_cmdline_user_args(): get_node("WorldClock").set_time(1, 15.0)
	if "--inspect-exterior" in OS.get_cmdline_user_args(): _exterior_camera()
	if "--inspect-facade" in OS.get_cmdline_user_args(): _facade_camera()
	if "--inspect-gate" in OS.get_cmdline_user_args(): _gate_camera()
	if "--inspect-lamp" in OS.get_cmdline_user_args(): _lamp_camera()
	auto_replay = "--replay" in OS.get_cmdline_user_args()
	if auto_replay:
		await get_tree().create_timer(3.0).timeout
		_start_replay()

func _input(event: InputEvent) -> void:
	if not review_mode: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F2 or event.keycode == KEY_F2: _start_replay()
		if event.physical_keycode == KEY_F3 or event.keycode == KEY_F3: _exterior_camera()
		if event.physical_keycode == KEY_F6 or event.keycode == KEY_F6: _facade_camera()
		if event.physical_keycode == KEY_F7 or event.keycode == KEY_F7: _wall_camera()
		if event.physical_keycode == KEY_F8 or event.keycode == KEY_F8: _gate_camera()
		if event.physical_keycode == KEY_F9 or event.keycode == KEY_F9: _lamp_camera()
		if (event.physical_keycode == KEY_F4 or event.keycode == KEY_F4) and is_instance_valid(overview):
			if overview.current:
				get_node("Player").camera.make_current()
				_review_hud(true)
			else: _interior_camera()

func _exterior_camera() -> void:
	if not is_instance_valid(overview): return
	var shelter: Node3D = get_node("StartRun").shelter
	overview.global_position = shelter.to_global(Vector3(-175, 140, -270))
	overview.look_at(shelter.to_global(Vector3(0, 3, -194)))
	overview.make_current()
	_review_hud(false)

func _interior_camera() -> void:
	var shelter: Node3D = get_node("StartRun").shelter
	overview.global_position = shelter.to_global(Vector3(9, 4.7, -398))
	overview.look_at(shelter.to_global(Vector3(0, 2, -364)))
	overview.make_current()
	_review_hud(false)

func _facade_camera() -> void:
	if not is_instance_valid(overview): return
	var shelter: Node3D = get_node("StartRun").shelter
	overview.global_position = shelter.to_global(Vector3(-23, 2.4, 28))
	overview.look_at(shelter.to_global(Vector3(-7, 4.2, 12.5)))
	overview.make_current()
	_review_hud(false)

func _wall_camera() -> void:
	if not is_instance_valid(overview): return
	var shelter: Node3D = get_node("StartRun").shelter
	overview.global_position = shelter.to_global(Vector3(-13, 3.6, -112))
	overview.look_at(shelter.to_global(Vector3(3, 2.0, -76)))
	overview.make_current()
	_review_hud(false)

func _gate_camera() -> void:
	if not is_instance_valid(overview): return
	var shelter: Node3D = get_node("StartRun").shelter
	overview.global_position = shelter.to_global(Vector3(-6.4, 1.7, -326))
	overview.look_at(shelter.to_global(Vector3(-2.5, 1.6, -322.85)))
	overview.make_current()
	_review_hud(false)

func _lamp_camera() -> void:
	if not is_instance_valid(overview): return
	var shelter: Node3D = get_node("StartRun").shelter
	overview.global_position = shelter.to_global(Vector3(-12, 5.1, -317))
	overview.look_at(shelter.to_global(Vector3(-9, 6.9, -312)))
	overview.make_current()
	_review_hud(false)

func _review_hud(visible: bool) -> void:
	# Inspection cameras must not show interaction prompts from the parked player.
	for layer: CanvasLayer in get_node("Player").find_children("*", "CanvasLayer", true, false):
		if layer.get_parent() is RayCast3D: layer.visible = visible

func _start_replay() -> void:
	if not review_mode or replay_started or not is_instance_valid(replay_vehicle): return
	for inner_gate in get_node("StartRun").shelter.get_node("Gates").get_children():
		inner_gate.move_to(true)
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
	for z in [-326.0, -286.0, -246.0, -198.0, -158.0, -118.0, -78.0, -38.0, 4.0]:
		route.append(run.shelter.to_global(Vector3(0, 0, z)))
	var site: Dictionary = run.shelter_site
	# Road-relative points create a broad left turn from the east-side garage.
	for point in [Vector3(24, 0, 0), Vector3(17, 0, 0), Vector3(10, 0, -2), Vector3(4, 0, -9), Vector3(0, 0, -22), Vector3(0, 0, -65)]:
		route.append(site.road * point)
	_interior_camera()
	replay_running = true
	print("TUTORIAL_DRIVE_BEGIN: production wheels, normal fuel, no repositioning")

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
	var desired_speed := 4.0 if route_index < 9 else 3.0
	replay_vehicle.control_override = {"throttle": clampf((desired_speed - speed) * 0.6, 0.0, 0.65), "brake": clampf((speed - desired_speed) * 0.8, 0.0, 1.0), "steering": steering}
	var run: Node = get_node("StartRun")
	if replay_vehicle.global_position.x >= 29.0:
		overview.global_position = replay_vehicle.global_position + Vector3(8, 4, 5)
		overview.look_at(replay_vehicle.global_position + Vector3(-8, 1, 0))
	else:
		overview.global_position = replay_vehicle.global_position + Vector3(12, 9, 14)
		overview.look_at(replay_vehicle.global_position + Vector3(0, 1, -4))
	status.text = "WHEEL DRIVE  %.1f m/s | route %d/15 | gate %s" % [speed, route_index + 1, run.phase]
	if replay_vehicle.global_position.y < -2 or replay_vehicle.global_basis.y.y < 0.65:
		_finish(false, "lost ground support or rolled over")
	elif replay_time > 240.0:
		_finish(false, "departure timed out at %s" % replay_vehicle.global_position)
	elif route_index == route.size() - 1 and distance < 5:
		_finish(run.phase == "sealed", "exited, turned onto forward highway and garage " + run.phase)

func _finish(ok: bool, detail: String) -> void:
	replay_running = false
	if is_instance_valid(replay_vehicle):
		replay_vehicle.control_override = {"brake": 1.0}
		replay_vehicle.set_handbrake(true)
		replay_vehicle.set_engine_running(false)
	var message := "%s: TUTORIAL_WHEEL_DEPARTURE %s (%.1fs)" % ["PASS" if ok else "FAIL", detail, replay_time]
	print(message)
	if status != null: status.text = message
	if not ok: push_error(message)
	if auto_replay and "--keep-open" not in OS.get_cmdline_user_args():
		await get_tree().create_timer(3.0).timeout
		get_tree().quit(0 if ok else 1)
