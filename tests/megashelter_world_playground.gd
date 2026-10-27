extends "res://tests/megashelter_playground.gd"
## Actual scheduled site, production terrain, navigation and streaming.
var site: Dictionary

func _enter_tree() -> void:
	# The fixture is far beyond the opening tutorial and never restores a save.
	var opening := get_node("StartRun")
	remove_child(opening)
	opening.free()
	var world_seed := 6
	var row := 33
	var column := 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-seed="): world_seed = arg.trim_prefix("--world-seed=").to_int()
		if arg.begins_with("--row="): row = arg.trim_prefix("--row=").to_int()
		if arg.begins_with("--column="): column = arg.trim_prefix("--column=").to_int()
	var profile := WorldProfile.new()
	profile.chunks_ahead = 1
	profile.chunks_behind = 1
	var field := WorldField.new(world_seed, profile)
	site = field.offroad_site(row, column)
	if site.is_empty() or site.definition_id != "modular_megashelter":
		push_error("Requested cell does not contain a scheduled megashelter")
		get_tree().quit(1)
		return
	plan = site.exterior_plan
	seed_value = plan.seed
	template_index = plan.template
	$WorldGenerator.world_seed = world_seed
	$WorldGenerator.profile = profile
	var band := floori(float(site.s) / 150.0)
	$WorldGenerator.restore_bands.assign(range(band - 1, band + 2))
	$Player.transform = site.building * Transform3D(Basis.IDENTITY, plan.access_point + Vector3(7, 0.5, 3))
	$NewRv.transform = site.building * Transform3D(Basis.IDENTITY, Vector3(-10, 1.8, float(plan.depth) * 0.5 + 19))
	get_tree().node_added.connect(_freeze_enemy)

func _ready() -> void:
	get_window().title = "ApocalypseRV - Scheduled Megashelter"
	get_window().size = Vector2i(1280, 800)
	player = $Player
	vehicle = $NewRv/Chassis
	clock = $WorldClock
	clock.running = false
	clock.weather_running = false
	clock.set_time(1, 14)
	clock.weather.set_weather(Vector3.ZERO, true)
	camera = Camera3D.new()
	camera.far = 450
	camera.fov = 68
	add_child(camera)
	var deadline := Time.get_ticks_msec() + 90000
	while ($WorldGenerator.building or $WorldGenerator.active_chunks.is_empty()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	for entry in $WorldGenerator.active_chunks:
		for child in entry.node.get_children():
			if child.get_meta("poi_id", "") == site.id: building = child
	if not is_instance_valid(building):
		push_error("Scheduled megashelter did not stream in")
		get_tree().quit(1)
		return
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(18, 185)
	layer.add_child(label)
	label.text = "SCHEDULED MEGASHELTER / %s\nF2 exterior  F3 entrance  F4 walk  F9 capture  F10 parking" % site.id
	_overview()
	print("SCHEDULED_MEGASHELTER_READY ", site.id, " position=", site.building.origin)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(2).timeout
		await _capture("world")
		_entrance()
		await get_tree().create_timer(0.5).timeout
		await _capture("world-entry")
		if "--quit-after-review" in OS.get_cmdline_user_args(): get_tree().quit()
	elif "--replay" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.0).timeout
		_drive()

func _freeze_enemy(node: Node) -> void:
	if node is Monster: node.process_mode = Node.PROCESS_MODE_DISABLED

func _overview() -> void:
	camera.fov = 90
	camera.global_position = site.building * Vector3(float(plan.width) * 0.65, 8, float(plan.depth) * 0.5 + float(plan.height) * 0.65)
	# The natural hill beyond the flattened apron can rise above the site.
	var surface_height: float = $WorldGenerator.field.height_at(camera.global_position.x, camera.global_position.z)
	camera.global_position.y = maxf(camera.global_position.y, surface_height + 8.0)
	camera.look_at(site.building * Vector3(0, float(plan.height) * 0.44, 0))
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("MEGASHELTER_WORLD_VIEW camera=", camera.global_position, " ground=", surface_height, " target=", site.building * Vector3(0, float(plan.height) * 0.44, 0))

func _entrance() -> void:
	camera.fov = 68
	camera.global_position = site.building * Vector3(16, 3.1, float(plan.depth) * 0.5 + 24)
	camera.look_at(site.building * Vector3(0, 4.2, float(plan.depth) * 0.5))
	camera.make_current()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F2: _overview()
		KEY_F3: _entrance()
		KEY_F4:
			(player.get("camera") as Camera3D).make_current()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		KEY_F9: _capture("world-manual")
		KEY_F10: _drive()

func _drive_leg(reverse: bool, target_z: float) -> bool:
	# Keep both ends of the 12m RV inside the authored clear forecourt.
	if reverse: target_z = minf(target_z, float(plan.depth) * 0.5 + 23.0)
	vehicle.gear = -1 if reverse else 4
	var target: Vector3 = site.building * Vector3(-10, 0, target_z)
	for frame in range(1800):
		var local_position: Vector3 = site.building.affine_inverse() * vehicle.global_position
		var remaining := target_z - local_position.z if reverse else local_position.z - target_z
		if remaining < 1.5: return true
		var speed := vehicle.linear_velocity.length()
		var local: Vector3 = vehicle.global_transform.affine_inverse() * target
		var angle := atan2(local.x, local.z) if reverse else atan2(-local.x, -local.z)
		var steering := clampf(angle * (-1.8 if reverse else 1.8) / vehicle.max_steering, -1, 1)
		vehicle.control_override = {"throttle": clampf((2.5 - speed) * 0.7, 0, 1), "brake": clampf((speed - 3) * 0.5, 0, 1), "steering": steering}
		label.text = "WORLD PARKING / %s / %.1f m / %.1f m/s" % ["depart" if reverse else "approach", remaining, speed]
		await get_tree().physics_frame
	return false
