extends Node3D

class CoverageDial extends DeviationPressure:
	var override_strength := -1.0

	func signal_strength_at(point: Vector3) -> float:
		if override_strength >= 0.0: return override_strength
		return super.signal_strength_at(point)

var world: Node3D
var rv: Chassis
var player: CharacterBody3D
var coverage := CoverageDial.new()
var field: WorldField
var road_s := 520.0
var speaker: DispatchSpeaker

func _ready() -> void:
	get_window().title = "ApocalypseRV - Dispatch Speaker"
	world = preload("res://world/test_world.tscn").instantiate()
	var generator := world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = WorldProfile.new()
	field = WorldField.new(generator.world_seed, generator.profile)
	coverage.name = "DeviationPressure"
	world.add_child(coverage)
	world.get_node("NewRv").transform = Transform3D.IDENTITY
	rv = world.get_node("NewRv/Chassis")
	player = world.get_node("Player")
	speaker = rv.get_node("DispatchSpeaker")
	rv.transform = _pose(road_s, 0)
	player.position = rv.position + Vector3.UP * 2.0
	add_child(world)
	await world.wait_for_play()
	rv.handbrake = true
	rv.set_engine_running(true)
	rv.set_gear(1)
	rv.get_node("DriverSeat").interact_hold(player)
	world.get_node("WorldClock").set_time(1, 12)
	var controls := PlaygroundControls.new()
	add_child(controls)
	controls.section("Dispatch speaker")
	controls.note("Broadcasts are read from the word bank. Captions: Settings > Audio > Broadcast Captions.")
	controls.button("Play next broadcast", func(): if is_instance_valid(speaker): speaker.receive())
	controls.readout("Last line", func(): return speaker.schedule.caption if is_instance_valid(speaker) and not speaker.schedule.caption.is_empty() else "Carrier tone")
	controls.slider("Signal override", 0.0, 1.0, 0.01, 1.0, func(s: float): coverage.override_strength = s)
	controls.button("Use route coverage", func(): coverage.override_strength = -1.0)
	controls.readout("Reception", func(): return "%s  %.0f%%" % [speaker.get_status(), speaker.strength * 100] if is_instance_valid(speaker) else "Removed")
	controls.buttons([["Road", _park.bind(road_s, 0.0)],
		["Forest edge", _park.bind(road_s, (RoutePressureState.FOREST_SAFE + RoutePressureState.FOREST_START) * 0.5)],
		["Deep forest", _park.bind(road_s, RoutePressureState.FOREST_START + 15.0)],
		["Backtrack", _park.bind(road_s - RoutePressureState.BACKTRACK_START - 10.0, 0.0)]])
	controls.buttons([["Drain battery", _battery.bind(false)], ["Refill battery", _battery.bind(true)]])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("DISPATCH_PLAYGROUND_READY seated=", is_instance_valid(rv.get_node("DriverSeat").current_driver))
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()

func _pose(progress: float, offset: float) -> Transform3D:
	var frame := field.road_frame(progress)
	if offset > 0:
		var query := field.road_query(frame.origin.x, frame.origin.z)
		frame.origin += frame.basis.x * (offset + float(query.width) * 0.5)
	frame.origin.y = field.height_at(frame.origin.x, frame.origin.z) + 1.25
	return frame

func _park(progress: float, offset: float) -> void:
	coverage.override_strength = -1.0
	var pose := _pose(progress, offset)
	rv.global_transform = pose
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	rv.reset_physics_interpolation()
	rv.handbrake = true
	if not is_instance_valid(rv.get_node("DriverSeat").current_driver):
		player.global_position = pose * Vector3(0.0, 0.7, -3.0)
		player.velocity = Vector3.ZERO

func _battery(full: bool) -> void:
	if not full: rv.set_engine_running(false)
	rv.current_power = rv.max_power if full else 0.0

func _capture() -> void:
	var folder := "res://.godot/dispatch-captures/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await get_tree().create_timer(1.0).timeout
	await _snapshot(folder + "driver.png")
	var camera := Camera3D.new()
	camera.cull_mask = get_viewport().get_camera_3d().cull_mask
	speaker.add_child(camera)
	camera.position = Vector3(-0.19, -0.09, 0.91)
	camera.look_at(speaker.to_global(Vector3(0, -0.05, 0.04)))
	camera.fov = 42.0
	camera.make_current()
	# Inspection light for the close-up only; the driver view uses normal cabin lighting.
	var light := OmniLight3D.new()
	speaker.add_child(light)
	light.position = Vector3(-0.3, 0.13, 0.8)
	light.light_color = Color("fff3dd")
	light.light_energy = 0.85
	light.omni_range = 1.8
	HUDVisibility.set_cinematic(get_viewport(), true)
	await _snapshot(folder + "panel.png")
	rv.get_node("DriverSeat/Camera3D").make_current()
	HUDVisibility.set_cinematic(get_viewport(), false)
	camera.queue_free()
	light.queue_free()
	await get_tree().process_frame
	world.queue_free()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().quit(0)

func _snapshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE: ", path, " ", error_string(error))
