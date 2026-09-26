extends "res://tests/production_gas_station_playground.gd"
## Uses the same wheel-driven approach controller as the production station fixture.
var minor_seed := 0
var minor_cell := 0

func _enter_tree() -> void:
	# Intentionally bypass the station fixture's fixed stop(1) setup.
	set_meta("entity_domain", true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): minor_seed = arg.trim_prefix("--seed=").to_int()
		if arg.begins_with("--cell="): minor_cell = arg.trim_prefix("--cell=").to_int()
	var profile := WorldProfile.new()
	var field := WorldField.new(minor_seed, profile)
	site = field.minor_site(minor_cell)
	while site.is_empty():
		minor_cell += 1
		site = field.minor_site(minor_cell)
	$WorldGenerator.world_seed = minor_seed
	$WorldGenerator.profile = profile
	var band := floori(float(site.s) / 150)
	$WorldGenerator.restore_bands.assign(range(band - 2, band + 4))
	$Player.position = site.building * Vector3(0, 0.3, 10)
	$NewRv/Chassis.transform = field.road_frame(float(site.s) - 35)
	$NewRv/Chassis.position.y += 1.8
	# Keep AI out of the parking measurement; the production encounters remain enabled.
	get_tree().node_added.connect(_freeze_fixture_enemy)

func _freeze_fixture_enemy(node: Node) -> void:
	if node is Monster: node.process_mode = Node.PROCESS_MODE_DISABLED

func _ready() -> void:
	await super._ready()
	get_window().title = "ApocalypseRV - Production Roadside POI"
	status.text = "%s / seed %d / cell %d / side %d\nF2 overview / F3 walk / F5 wheel-driven entry and exit / F7 capture" % [site.definition_id, minor_seed, minor_cell, site.side]
	print("PRODUCTION_MINOR_READY ", site.definition_id, " side=", site.side, " s=", site.s)

func _view() -> void:
	observer.position = site.building * Vector3(24, 17, 32)
	observer.look_at(site.building * Vector3(0, 1, 0))
	observer.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/production-minor-%d-%d.png" % [minor_seed, minor_cell])

func _drive() -> void:
	await super._drive()
	if not status.text.begins_with("PASS:"):
		if "--quit-after-replay" in OS.get_cmdline_user_args(): get_tree().quit(1)
		return
	driving = true
	var vehicle: Chassis = $NewRv/Chassis
	vehicle.handbrake = false
	vehicle.gear = -1
	$NewRv/Chassis/DriverSeat.interact_hold($Player)
	observer.make_current()
	var leg := 0
	var points: Array[Vector3] = []
	# Reverse along the clear approach instead of attempting a 12m-RV U-turn.
	for p in [Vector3(23,0,3), Vector3(8,0,14), Vector3(0,0,18)]:
		p.x *= float(site.side)
		points.append(site.road * p)
	for frame in range(3000):
		var target := points[leg]
		var offset := vehicle.global_position - target
		offset.y = 0
		if offset.length() < 3.5:
			leg += 1
			if leg == points.size(): break
			target = points[leg]
		var local := vehicle.global_transform.affine_inverse() * target
		var angle := atan2(local.x, local.z)
		var speed := vehicle.linear_velocity.length()
		var limit := lerpf(vehicle.max_steering, vehicle.max_steering * 0.3, clampf(speed / vehicle.max_speed, 0, 1))
		vehicle.control_override = {"throttle": clampf((2.5 - speed) * 0.6, 0, 1), "brake": clampf((speed - 3.5) * 0.3, 0, 1), "steering": clampf(-angle * 1.8 / limit, -1, 1)}
		status.text = "EXIT / waypoint %d / %.1f m/s" % [leg + 1, speed]
		await get_tree().physics_frame
	# Once back on the highway, drive away in forward gear. Continuing to
	# reverse uphill tests reverse torque rather than the site's access route.
	var departed := false
	if leg == points.size():
		vehicle.control_override = {"throttle": 0.0, "brake": 1.0, "steering": 0.0}
		for frame in range(90): await get_tree().physics_frame
		vehicle.gear = 4
		var departure: Vector3 = $WorldGenerator.field.road_frame(float(site.s) + 40).origin
		for frame in range(1500):
			var offset := vehicle.global_position - departure
			offset.y = 0
			if offset.length() < 4:
				departed = true
				break
			var local := vehicle.global_transform.affine_inverse() * departure
			var angle := atan2(-local.x, -local.z)
			var speed := vehicle.linear_velocity.length()
			var limit := lerpf(vehicle.max_steering, vehicle.max_steering * 0.3, clampf(speed / vehicle.max_speed, 0, 1))
			vehicle.control_override = {"throttle": clampf((4.0 - speed) * 0.6, 0, 1), "brake": clampf((speed - 5.0) * 0.3, 0, 1), "steering": clampf(angle * 1.8 / limit, -1, 1)}
			status.text = "DEPART / %.1f m/s" % speed
			await get_tree().physics_frame
	vehicle.control_override = {}
	vehicle.handbrake = true
	driving = false
	status.text = "PASS: minor POI wheel-driven entry and exit" if departed else "FAIL: minor POI exit route blocked"
	print(status.text, " seed=", minor_seed, " cell=", minor_cell, " side=", site.side)
	print("MINOR_EXIT leg=", leg, " road_local=", site.road.affine_inverse() * vehicle.global_position, " speed=", vehicle.linear_velocity.length())
	if DisplayServer.get_name() != "headless": await _capture()
	if "--quit-after-replay" in OS.get_cmdline_user_args(): get_tree().quit(0 if departed else 1)
