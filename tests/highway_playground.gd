extends Node3D
## F6 drives using production input/VehicleBody3D. No path-driven vehicle transforms.
var running := false
var status: Label
var vehicle: Chassis
var camera: Camera3D
var frames_ms: Array[float] = []
var route_target := 5100.0
var simulation_time := 0.0
var max_lateral := 0.0
var max_roll := 0.0
var last_progress := 0.0
var stalled_time := 0.0
var last_tick: int
var preview_busy := false
var parking_replay := false
var parking_site: Dictionary
var parking_leg := 0
var parking_reverse := false
var parking_pause := 0.0
var parking_points: Array[Vector3] = []
var parking_recorded := false

func _ready() -> void:
	$Zombie.queue_free()
	vehicle = $NewRv/Chassis
	vehicle.contact_monitor = true
	vehicle.max_contacts_reported = 32
	print("HARDWARE engine=", Engine.get_version_info().string, " cpu=", OS.get_processor_name(), " renderer=", RenderingServer.get_video_adapter_name())
	var layer := CanvasLayer.new()
	layer.layer = 35
	add_child(layer)
	status = Label.new()
	status.position = Vector2(24, 64)
	status.add_theme_font_size_override("font_size", 20)
	status.text = "F6: 5km drive | F7: parking round trip | F1/F2/F3: landscapes"
	layer.add_child(status)
	camera = Camera3D.new()
	camera.far = 1500.0
	add_child(camera)
	last_tick = Time.get_ticks_usec()
	parking_replay = "--parking" in OS.get_cmdline_user_args()
	if "--replay" in OS.get_cmdline_user_args() or parking_replay:
		_start.call_deferred()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F6 and not running:
			parking_replay = false
			_start()
		if event.keycode == KEY_F7 and not running:
			parking_replay = true
			_start()
		if event.keycode in [KEY_F1, KEY_F2, KEY_F3] and not running and not preview_busy:
			_preview((event.keycode - KEY_F1) * 900.0 + 300.0)

func _preview(s: float) -> void:
	preview_busy = true
	$WorldGenerator.set_process(false)
	while $WorldGenerator.next_band <= floori(s / 150.0) + 3:
		await $WorldGenerator._spawn_band($WorldGenerator.next_band, true)
		$WorldGenerator.next_band += 1
	var frame: Transform3D = $WorldGenerator.field.road_frame(s)
	camera.position = frame * Vector3(38, 24, 40)
	camera.look_at(frame.origin + Vector3(0, 2, -35))
	camera.current = true
	status.text = "LANDSCAPE %dm / seed 42 | F1 grass / F2 woodland / F3 rocky hills" % s
	preview_busy = false

func _start() -> void:
	if running:
		return
	if parking_recorded or simulation_time > 0:
		# A fresh fixture preserves streaming's intentionally one-way contract.
		get_tree().reload_current_scene()
		return
	for monster in get_tree().get_nodes_in_group(Groups.MONSTERS):
		monster.queue_free()
	# Controlled fixture setup only. Once started, all motion is wheel driven.
	vehicle.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.8, -20))
	if parking_replay:
		parking_site = $WorldGenerator.field.stop(1)
		vehicle.global_transform = $WorldGenerator.field.road_frame(float(parking_site.s) - 35.0)
		vehicle.position.y += 1.8
		for point in [Vector3(8, 0, 14), Vector3(23, 0, 3), Vector3(33, 0, -4)]:
			point.x *= float(parking_site.side)
			parking_points.append(parking_site.road * point)
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.current_fuel = 100.0
	vehicle.set_engine_running(true)
	vehicle.handbrake = false
	vehicle.gear = 4
	vehicle.fuel_drive_burn_per_second = 0.0
	vehicle.fuel_idle_burn_per_second = 0.0
	$WorldGenerator.set_process(true)
	for i in range(30):
		await get_tree().physics_frame
	$NewRv/Chassis/DriverSeat.interact_hold($Player)
	camera.current = true
	running = true
	last_tick = Time.get_ticks_usec()
	print("DRIVE START seed=42 target=5100; fuel consumption disabled in fixture only")

func _physics_process(delta: float) -> void:
	if not running:
		return
	var now := Time.get_ticks_usec()
	frames_ms.append((now - last_tick) / 1000.0)
	last_tick = now
	simulation_time += delta
	var field: WorldField = $WorldGenerator.field
	var position_now := vehicle.global_position
	var s := -position_now.z
	var query := field.road_query(position_now.x, position_now.z)
	max_lateral = maxf(max_lateral, float(query.distance))
	max_roll = maxf(max_roll, acos(clampf(vehicle.global_basis.y.dot(Vector3.UP), -1, 1)))
	var speed := vehicle.linear_velocity.length()
	var target := field.road_frame(s + clampf(speed * 1.2, 10.0, 22.0)).origin
	if parking_replay:
		if parking_pause > 0:
			parking_pause -= delta
			_release()
			vehicle.is_player_driving = false
			vehicle.handbrake = true
			return
		vehicle.is_player_driving = true
		vehicle.handbrake = false
		target = parking_points[parking_leg]
		if Vector2(position_now.x - target.x, position_now.z - target.z).length() < 2.5:
			parking_leg += 1
			if parking_leg == parking_points.size():
				if not parking_recorded:
					parking_recorded = true
					parking_pause = 2.0
					parking_reverse = true
					parking_leg = 0
					parking_points = [parking_site.road * Vector3(float(parking_site.side) * 23, 0, 3), parking_site.road * Vector3(float(parking_site.side) * 8, 0, 14), parking_site.road * Vector3(0, 0, 35)]
					print("PARK: reached clear bay; reversing along approach")
				elif parking_reverse:
					parking_reverse = false
					parking_pause = 2.0
					parking_leg = 0
					parking_points = [field.road_frame(float(parking_site.s) + 45.0).origin]
				else:
					_finish(true, "parked at roadside site and returned to highway using wheels")
					return
			target = parking_points[parking_leg]
	var local := vehicle.global_transform.affine_inverse() * target
	var angle := atan2(-local.x, local.z if parking_reverse else -local.z)
	var dynamic_steering := lerpf(vehicle.max_steering, vehicle.max_steering * 0.3, clampf(speed / vehicle.max_speed, 0, 1))
	var steering := clampf(angle * 1.8 / dynamic_steering, -1, 1)
	var desired_speed := 10.0 if field.road_width(s + 25) < 13.0 else 15.0
	if parking_replay:
		desired_speed = 3.0 if parking_reverse else 4.0
	Input.action_press("move_left", maxf(steering, 0.0))
	Input.action_press("move_right", maxf(-steering, 0.0))
	Input.action_press("move_forward", clampf((desired_speed - speed) * 0.6, 0.0, 1.0))
	Input.action_press("move_back", clampf((speed - desired_speed - 1) * 0.3, 0.0, 1.0))
	vehicle.gear = -1 if parking_reverse else 4
	camera.position = position_now + vehicle.global_basis * Vector3(0, 7, 13)
	camera.look_at(position_now + vehicle.global_basis * Vector3(0, 1, -18))
	status.text = "DRIVE %dm / 5100m | %.1f m/s | %d chunks" % [s, speed, $WorldGenerator.active_chunks.size()]
	if s > last_progress + 50:
		last_progress = s
		stalled_time = 0.0
	else:
		stalled_time += delta
	var off_route := float(query.distance) > field.road_width(s) * 0.5 - 1.7
	if parking_replay:
		off_route = field.court_distance(position_now.x, position_now.z, parking_site) > 6 and float(query.distance) > field.road_width(s) * 0.5
		stalled_time = 0.0
	if position_now.y < field.height_at(position_now.x, position_now.z) - 3 or absf(vehicle.global_basis.y.y) < 0.5 or off_route or stalled_time > 35 or (parking_replay and simulation_time > 150):
		_finish(false, "off-road / rollover / unsupported / stalled at %.1f speed %.1f lateral %.2f" % [s, speed, query.distance])
	elif s >= route_target:
		_finish(true, "5 km completed using production wheels and controls")

func _finish(okay: bool, reason: String) -> void:
	running = false
	_release()
	vehicle.is_player_driving = false
	frames_ms.sort()
	var p95 := frames_ms[mini(frames_ms.size() - 1, floori(frames_ms.size() * 0.95))]
	var p99 := frames_ms[mini(frames_ms.size() - 1, floori(frames_ms.size() * 0.99))]
	var summary := "%s: DRIVE %s; sim=%.1fs lateral=%.2fm tilt=%.1fdeg frame p95=%.2fms p99=%.2fms max=%.2fms memory=%.1fMiB chunks=%d" % ["PASS" if okay else "FAIL", reason, simulation_time, max_lateral, rad_to_deg(max_roll), p95, p99, frames_ms.back(), OS.get_static_memory_usage() / 1048576.0, $WorldGenerator.active_chunks.size()]
	print(summary)
	status.text = summary
	if not okay:
		push_error(summary)
	if "--replay" in OS.get_cmdline_user_args() or "--parking" in OS.get_cmdline_user_args():
		get_tree().quit(0 if okay else 1)

func _release() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(action)
func _exit_tree() -> void:
	_release()
