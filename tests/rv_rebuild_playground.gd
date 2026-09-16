extends "res://tests/rv_design_workshop.gd"
var extra_view: int = 0
var result: String = ""
var night: bool = false
var driving_replay: bool = false
var drive_time: float = 0.0
var drive_start := Vector3.ZERO
var peak_speed: float = 0.0
var forward_distance: float = 0.0
var reverse_start := Vector3.ZERO
var replay_heading: float = 0.0
func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - Engine and Boarding Workshop"
	var key := InputEventKey.new()
	key.keycode = KEY_E
	InputMap.action_add_event("interact", key)
	if "--drive" in OS.get_cmdline_user_args(): _start_drive()
func _process(delta: float) -> void:
	super._process(delta)
	instructions.text += "\nF8 引擎艙（E 開蓋） · F9 後門／坡板 · F10 故障儀表 · F11 夜間 · F12 輪驅回放\n" + result
	if extra_view == 2:
		observer.position = rv.to_global(Vector3(6, 3, 11))
		observer.look_at(rv.to_global(Vector3(0, 0.5, 6.8)))
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode in [KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7]: extra_view = 0
	super._unhandled_input(event)
	match event.keycode:
		KEY_F8:
			_stop_demo()
			extra_view = 1
			view = 5
			player.camera.global_position = rv.to_global(Vector3(0, 0.5, -8.2))
			player.camera.look_at(rv.engine_bay.global_position)
			player.camera.current = true
			player.get_node("Camera3D/InteractRay").force_raycast_update()
		KEY_F9:
			_stop_demo()
			extra_view = 2
			view = 5
			observer.current = true
			rv.get_node("RearDoor").restore_angles([-deg_to_rad(100), deg_to_rad(100)])
			await get_tree().physics_frame
			result = rv.rear_ramp.interact(player)
		KEY_F10:
			extra_view = 0
			view = 2
			rv.current_fuel = 8
			rv.current_power = 12
			rv.get_engine().health = 100
			rv.wheel_health[0] = 20
			rv.headlights_requested = true
			seat.interact_hold(player)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		KEY_F11:
			night = not night
			rv.current_power = 100
			for node in get_children():
				if node is DirectionalLight3D: node.light_energy = 0.02 if night else 1.3
				if node is WorldEnvironment: node.environment.ambient_light_energy = 0.06 if night else 0.5
			rv.headlights_requested = night
		KEY_F12: _start_drive()
func _start_drive() -> void:
	driving_replay = true
	drive_time = 0
	peak_speed = 0
	drive_start = rv.global_position
	replay_heading = rv.rotation.y
	rv.current_fuel = 65
	rv.current_power = 100
	rv.get_engine().health = 450
	rv.headlights_requested = true
	rv.set_engine_running(true)
	rv.handbrake = false
	rv.set_gear(1)
	seat.interact_hold(player)
	view = 0
	observer.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
func _physics_process(delta: float) -> void:
	if not driving_replay: return
	drive_time += delta
	peak_speed = maxf(peak_speed, rv.linear_velocity.length())
	if drive_time < 5:
		rv.control_override = {"throttle": 0.7, "steering": 0.18 if drive_time > 2 else 0.0}
	elif drive_time < 9:
		rv.control_override = {"brake": 1.0}
	elif drive_time < 13:
		if rv.gear != -1:
			forward_distance = rv.global_position.distance_to(drive_start)
			reverse_start = rv.global_position
			rv.set_gear(-1)
			rv.handbrake = false
		rv.control_override = {"throttle": 0.8}
	elif drive_time < 16:
		rv.control_override = {"brake": 1.0}
	else:
		driving_replay = false
		rv.control_override.clear()
		rv.handbrake = true
		rv.set_engine_running(false)
		result = "WHEEL REPLAY | forward %.2fm | reverse %.2fm | peak %.2fm/s | stopped %.2fm/s | yaw %.2f" % [forward_distance, rv.global_position.distance_to(reverse_start), peak_speed, rv.linear_velocity.length(), rv.rotation.y - replay_heading]
		print(result)
