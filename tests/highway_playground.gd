extends Node3D
## F6 drives using production input/VehicleBody3D. No path-driven vehicle transforms.
const WAIT = preload("res://tests/support/test_wait.gd")
var running := false
var starting := false
var stopping := false
var status: Label
var vehicle: Chassis
var camera: Camera3D
var frames_ms: Array[float] = []
var route_start := 0.0
var route_target := 5100.0
var driver_view := false
var keep_open := false
var argument_error := ""
var simulation_time := 0.0
var max_lateral := 0.0
var max_roll := 0.0
var last_progress := 0.0
var stalled_time := 0.0
var maximum_stall := 0.0
var off_route_time := 0.0
var off_route_seen := false
var start_height := 0.0
var minimum_height := INF
var maximum_height := -INF
var climbed := 0.0
var descended := 0.0
var last_height := 0.0
var reported_progress := 0.0
var stop_time := 0.0
var cleaned_chunks: Dictionary = {}
var removed_obstacles := 0
var last_tick: int
var preview_busy := false
var parking_replay := false
var parking_site: Dictionary
var parking_leg := 0
var parking_reverse := false
var parking_pause := 0.0
var parking_points: Array[Vector3] = []
var parking_recorded := false

func _enter_tree() -> void:
	var arguments := OS.get_cmdline_user_args()
	parking_replay = "--parking" in arguments
	driver_view = "--driver-view" in arguments
	keep_open = "--keep-open" in arguments
	for argument in arguments:
		if not argument.begins_with("--from=") and not argument.begins_with("--to="): continue
		var value := argument.get_slice("=", 1)
		if not value.is_valid_float() or not is_finite(float(value)):
			argument_error = "Route arguments require finite metres: " + argument
		elif argument.begins_with("--from="):
			route_start = float(value)
		else:
			route_target = float(value)
	if route_start < 0.0 or route_target <= route_start:
		argument_error = "Require 0 <= --from < --to"
	# Parent enters before child ready: build only the requested local bands,
	# using the production route profile instead of first loading the origin.
	var generator := get_node("WorldGenerator")
	var settings := WorldProfile.new()
	settings.max_grade = 0.12
	generator.profile = settings
	generator.restoring_entities = true # Fixture isolation: no random actors.
	generator.set_process(false)
	var field := WorldField.new(generator.world_seed, settings)
	if parking_replay: _configure_parking(field)
	var center := floori(route_start / settings.chunk_length)
	for band in range(center - settings.chunks_behind, center + settings.chunks_ahead + 1):
		generator.restore_bands.append(band)
	vehicle = get_node("NewRv/Chassis")
	vehicle.freeze = true
	var pose := field.road_frame(route_start)
	pose.origin.y += 1.8
	vehicle.transform = get_node("NewRv").transform.affine_inverse() * pose
	var player := get_node("Player")
	player.position = pose.origin + pose.basis.x * 3.0 + Vector3.UP * 2.0
	player.process_mode = Node.PROCESS_MODE_DISABLED

func _ready() -> void:
	for monster in get_tree().get_nodes_in_group(Groups.MONSTERS):
		monster.queue_free()
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
	status.text = "F6: route drive | F7: parking round trip | F8: driver/chase view | F1/F2/F3: landscapes"
	layer.add_child(status)
	camera = Camera3D.new()
	camera.far = 1500.0
	add_child(camera)
	start_height = $WorldGenerator.field.road_height(route_start)
	last_height = start_height
	minimum_height = start_height
	maximum_height = start_height
	last_tick = Time.get_ticks_usec()
	if not argument_error.is_empty():
		_finish(false, argument_error)
		return
	if "--replay" in OS.get_cmdline_user_args() or parking_replay:
		_start.call_deferred()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F6 and not running and not starting and not preview_busy:
			parking_replay = false
			_start()
		if event.keycode == KEY_F7 and not running and not starting and not preview_busy:
			parking_replay = true
			_start()
		if event.keycode == KEY_F8:
			driver_view = not driver_view
			_update_camera()
		if event.keycode in [KEY_F1, KEY_F2, KEY_F3] and not running and not starting and not preview_busy:
			_preview(route_start + (event.keycode - KEY_F1) * 900.0 + 300.0)

func _preview(s: float) -> void:
	preview_busy = true
	$WorldGenerator.set_process(false)
	var center := floori(s / 150.0)
	for band in range(center - 1, center + 2):
		if not $WorldGenerator.active_chunks.any(func(entry): return int(entry.index) == band):
			await $WorldGenerator._spawn_band(band, true)
	var frame: Transform3D = $WorldGenerator.field.road_frame(s)
	camera.position = frame * Vector3(38, 24, 40)
	camera.look_at(frame.origin + Vector3(0, 2, -35))
	camera.current = true
	status.text = "LANDSCAPE %dm / seed 42 | F6: route drive | F8: driver/chase view" % s
	preview_busy = false

func _configure_parking(field: WorldField) -> void:
	parking_site = field.stop(1)
	if parking_site.is_empty():
		argument_error = "The parking fixture's first roadside site is unavailable"
		return
	route_start = float(parking_site.s) - 35.0
	parking_points.clear()
	for point in [Vector3(8, 0, 14), Vector3(23, 0, 3), Vector3(33, 0, -4)]:
		point.x *= float(parking_site.side)
		parking_points.append(parking_site.road * point)

func _start() -> void:
	if running or starting:
		return
	if parking_recorded or simulation_time > 0:
		# A fresh fixture resets local startup bands and drive telemetry.
		get_tree().reload_current_scene()
		return
	starting = true
	$WorldGenerator.set_process(false)
	vehicle.freeze = true
	if parking_replay: _configure_parking($WorldGenerator.field)
	if not argument_error.is_empty():
		_finish(false, argument_error)
		return
	# Controlled fixture setup only. Once started, all motion is wheel driven.
	vehicle.global_transform = $WorldGenerator.field.road_frame(route_start)
	vehicle.position.y += 1.8
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.handbrake = true
	status.text = "Preparing local road collision and navigation..."
	# Generator.ready has already dispatched every restore band asynchronously.
	# A dispatched band is absent from active_chunks until construction finishes;
	# do not mistake it for missing geometry and launch a duplicate bake.
	if not await WAIT.until(get_tree(), func() -> bool:
		for band: int in $WorldGenerator.restore_bands:
			if not $WorldGenerator.active_chunks.any(func(entry): return int(entry.index) == band): return false
		return true):
		_finish(false, "initial local terrain publication timed out")
		return
	if not await WAIT.generator_idle(get_tree(), $WorldGenerator):
		_finish(false, "local terrain/navigation readiness timed out")
		return
	var center := floori(route_start / $WorldGenerator.profile.chunk_length)
	var added_bands := false
	for band in range(center - $WorldGenerator.profile.chunks_behind, center + $WorldGenerator.profile.chunks_ahead + 1):
		if not $WorldGenerator.active_chunks.any(func(entry): return int(entry.index) == band):
			# F7 can select parking after a manual launch at a different start.
			added_bands = true
			await $WorldGenerator._spawn_band(band, true)
	if added_bands and not await WAIT.generator_idle(get_tree(), $WorldGenerator):
		_finish(false, "local terrain/navigation readiness timed out")
		return
	_clean_fixture()
	await get_tree().physics_frame
	get_node("Player").process_mode = Node.PROCESS_MODE_INHERIT
	$NewRv/Chassis/DriverSeat.interact_hold($Player)
	if $NewRv/Chassis/DriverSeat.current_driver != $Player:
		_finish(false, "production driver seat refused the fixture player")
		return
	vehicle.freeze = false
	for i in range(90):
		await get_tree().physics_frame
	vehicle.current_fuel = 100.0
	vehicle.set_engine_running(true)
	vehicle.handbrake = false
	vehicle.gear = 4
	vehicle.fuel_drive_burn_per_second = 0.0
	vehicle.fuel_idle_burn_per_second = 0.0
	$WorldGenerator.set_process(true)
	start_height = $WorldGenerator.field.road_height(route_start)
	last_height = start_height
	minimum_height = start_height
	maximum_height = start_height
	last_progress = route_start
	reported_progress = route_start
	starting = false
	running = true
	_update_camera()
	last_tick = Time.get_ticks_usec()
	print("DRIVE START seed=42 from=%.1f to=%.1f start_height=%.2f; production wheels/Input; fixture fuel burn disabled, random actors/wrecks/spikes removed" % [route_start, route_target, start_height])

func _process(_delta: float) -> void:
	_clean_fixture()

func _clean_fixture() -> void:
	for monster in get_tree().get_nodes_in_group(Groups.MONSTERS):
		if not monster.is_queued_for_deletion(): monster.queue_free()
	for entry in $WorldGenerator.active_chunks:
		var chunk: ChunkGenerator = entry.node
		if not is_instance_valid(chunk) or cleaned_chunks.has(chunk.get_instance_id()): continue
		cleaned_chunks[chunk.get_instance_id()] = true
		# Only remove encounter props. Preserve terrain, trees, POIs and barriers.
		for child in chunk.get_children():
			if child is TireSpikeStrip or child.scene_file_path == RoadSpawns.WRECK_SCENE:
				child.queue_free()
				removed_obstacles += 1

func _ahead_s(field: WorldField, s: float, distance: float) -> float:
	# Route s is longitudinal Z, not metres travelled through a steep S bend.
	var previous := field.road_frame(s).origin
	while distance > 0.0:
		var next := field.road_frame(s + 2.0).origin
		var segment := Vector2(next.x - previous.x, next.z - previous.z).length()
		if segment >= distance: return s + 2.0 * distance / segment
		distance -= segment
		s += 2.0
		previous = next
	return s

func _curve_speed(field: WorldField, s: float) -> float:
	var maximum_curvature := 0.0
	var minimum_width := field.road_width(s)
	for sample in range(7):
		var before := Vector2(field.road_x(s - 2.0), -s + 2.0)
		var center := Vector2(field.road_x(s), -s)
		var after := Vector2(field.road_x(s + 2.0), -s - 2.0)
		var a := center - before
		var b := after - center
		maximum_curvature = maxf(maximum_curvature, absf(2.0 * a.cross(b)) / maxf(a.length() * b.length() * (after - before).length(), 0.001))
		minimum_width = minf(minimum_width, field.road_width(s))
		s = _ahead_s(field, s, 8.0)
	# Plan for 1m/s² lateral acceleration before entering each bend; narrower
	# carriageways retain extra margin for the production RV's swept footprint.
	var speed := clampf(sqrt(1.0 / maxf(maximum_curvature, 0.0001)), 4.0, 8.0)
	return minf(speed, 5.0) if minimum_width < 10.0 else speed

func _update_camera() -> void:
	if not is_instance_valid(camera): return
	var seat := vehicle.get_node("DriverSeat")
	if driver_view and seat.current_driver != null:
		seat.seat_camera.current = true
	else:
		camera.position = vehicle.global_position + vehicle.global_basis * Vector3(0, 7, 13)
		camera.look_at(vehicle.global_position + vehicle.global_basis * Vector3(0, 1, -18))
		camera.current = true

func _physics_process(delta: float) -> void:
	if not running:
		return
	var now := Time.get_ticks_usec()
	frames_ms.append((now - last_tick) / 1000.0)
	last_tick = now
	simulation_time += delta
	var field: WorldField = $WorldGenerator.field
	var position_now := vehicle.global_position
	var query := field.road_query(position_now.x, position_now.z)
	var s := float(query.s)
	max_lateral = maxf(max_lateral, float(query.distance))
	max_roll = maxf(max_roll, acos(clampf(vehicle.global_basis.y.dot(Vector3.UP), -1, 1)))
	var speed := vehicle.linear_velocity.length()
	var height := field.road_height(s)
	climbed += maxf(0.0, height - last_height)
	descended += maxf(0.0, last_height - height)
	last_height = height
	minimum_height = minf(minimum_height, height)
	maximum_height = maxf(maximum_height, height)
	var wheelbase := absf(Chassis.WHEEL_SLOTS[0].position.z - Chassis.WHEEL_SLOTS[2].position.z)
	var rear := vehicle.global_transform * Vector3(0, 0, Chassis.WHEEL_SLOTS[2].position.z)
	var rear_query := field.road_query(rear.x, rear.z)
	var lookahead := clampf(6.0 + speed * 0.75, 8.0, 13.0)
	var target := field.road_frame(_ahead_s(field, float(rear_query.s), lookahead)).origin
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
	var displacement := (target - rear).slide(Vector3.UP)
	var lateral := displacement.dot(vehicle.global_basis.x.slide(Vector3.UP).normalized())
	var steering_angle := atan(-2.0 * wheelbase * lateral / maxf(displacement.length_squared(), 1.0))
	var longitudinal_speed := absf(vehicle.linear_velocity.dot(-vehicle.global_basis.z))
	var steering_limit := lerpf(vehicle.max_steering, vehicle.max_steering * vehicle.high_speed_steering_ratio, clampf(longitudinal_speed / vehicle.max_speed, 0, 1))
	steering_limit = minf(steering_limit, atan(wheelbase * vehicle.steering_lateral_acceleration / maxf(1.0, longitudinal_speed * longitudinal_speed)))
	var steering := clampf(steering_angle / maxf(steering_limit, 0.001), -1.0, 1.0)
	var desired_speed := _curve_speed(field, s)
	if parking_replay:
		desired_speed = 3.0 if parking_reverse else 4.0
		# Preserve the existing low-speed parking manoeuvre controller.
		var local := vehicle.global_transform.affine_inverse() * target
		steering = clampf(atan2(-local.x, local.z if parking_reverse else -local.z) * 1.8 / steering_limit, -1.0, 1.0)
	else:
		var remaining := maxf(route_target - s, 0.0)
		# Reduce speed ahead of the endpoint; actual service brakes finish the run.
		desired_speed = minf(desired_speed, sqrt(2.0 * remaining))
		if remaining < 0.75: stopping = true
	if stopping:
		desired_speed = 0.0
		stop_time += delta
	Input.action_press("move_left", maxf(steering, 0.0))
	Input.action_press("move_right", maxf(-steering, 0.0))
	var braking := 1.0 if stopping else clampf((speed - desired_speed - 0.1) * 0.8, 0.0, 1.0)
	Input.action_press("move_forward", 0.0 if braking > 0.0 else clampf(0.2 + (desired_speed - speed) * 0.7, 0.0, 1.0))
	Input.action_press("move_back", braking)
	vehicle.gear = -1 if parking_reverse else 4
	_update_camera()
	status.text = "DRIVE %.0f -> %.0fm | at %.0fm / height %.1fm | %.1f / %.1f m/s | lateral %.2fm | %d chunks" % [route_start, route_target, s, height, speed, desired_speed, query.distance, $WorldGenerator.active_chunks.size()]
	if s > last_progress + 1.0:
		last_progress = s
		stalled_time = 0.0
	else:
		stalled_time += delta
	maximum_stall = maxf(maximum_stall, stalled_time)
	var off_route := float(query.distance) > float(query.width) * 0.5 - 1.7
	if parking_replay:
		off_route = field.court_distance(position_now.x, position_now.z, parking_site) > 6 and float(query.distance) > field.road_width(s) * 0.5
		stalled_time = 0.0
	off_route_seen = off_route_seen or off_route
	off_route_time = off_route_time + delta if off_route else 0.0
	if s > reported_progress + 100.0:
		reported_progress = s
		print("DRIVE SAMPLE s=%.1f height=%.2f speed=%.2f target=%.2f lateral=%.2f steering=%.3f brake=%.2f" % [s, height, speed, desired_speed, query.distance, steering_angle, braking])
	if position_now.y < field.height_at(position_now.x, position_now.z) - 3 or vehicle.global_basis.y.y < 0.5 or off_route_time > 0.3 or (not stopping and stalled_time > 20.0) or (parking_replay and simulation_time > 150) or stop_time > 25.0:
		_finish(false, "off-road / rollover / unsupported / stalled at %.1f speed %.1f lateral %.2f" % [s, speed, query.distance])
	elif stopping and speed < 0.15:
		_finish(true, "requested route completed and stopped using production wheels and brakes")

func _finish(okay: bool, reason: String) -> void:
	running = false
	starting = false
	_release()
	vehicle.handbrake = true
	vehicle.set_engine_running(false)
	vehicle.is_player_driving = false
	frames_ms.sort()
	var p95 := frames_ms[mini(frames_ms.size() - 1, floori(frames_ms.size() * 0.95))] if not frames_ms.is_empty() else 0.0
	var p99 := frames_ms[mini(frames_ms.size() - 1, floori(frames_ms.size() * 0.99))] if not frames_ms.is_empty() else 0.0
	var peak_frame: float = frames_ms.back() if not frames_ms.is_empty() else 0.0
	var end_s := float($WorldGenerator.field.road_query(vehicle.global_position.x, vehicle.global_position.z).s)
	var end_height: float = $WorldGenerator.field.road_height(end_s)
	var summary := "%s: DRIVE %s; from=%.1f requested_to=%.1f stopped_at=%.1f start_y=%.2f end_y=%.2f net=%.2fm climb=%.2fm descent=%.2fm range=%.2f..%.2fm sim=%.1fs lateral=%.2fm tilt=%.1fdeg off_route=%s max_stall=%.1fs obstacles_removed=%d frame p95=%.2fms p99=%.2fms max=%.2fms memory=%.1fMiB chunks=%d" % ["PASS" if okay else "FAIL", reason, route_start, route_target, end_s, start_height, end_height, end_height - start_height, climbed, descended, minimum_height, maximum_height, simulation_time, max_lateral, rad_to_deg(max_roll), off_route_seen, maximum_stall, removed_obstacles, p95, p99, peak_frame, OS.get_static_memory_usage() / 1048576.0, $WorldGenerator.active_chunks.size()]
	print(summary)
	status.text = summary
	if not okay:
		push_error(summary)
	if not keep_open and ("--replay" in OS.get_cmdline_user_args() or "--parking" in OS.get_cmdline_user_args()):
		get_tree().quit(0 if okay else 1)

func _release() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(action)
func _exit_tree() -> void:
	_release()
