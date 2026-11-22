extends Node3D
## Begin on foot beside a parked RV at the first actual station for this seed.
var site: Dictionary
var world_seed := 25

func _enter_tree() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): world_seed = arg.trim_prefix("--seed=").to_int()
	var field := WorldField.new(world_seed)
	for index in range(2, 600, 3):
		for candidate in field.sites_near_z(-index * field.profile.stop_spacing, 200):
			if candidate.definition_id == "mile_end":
				site = candidate
				break
		if not site.is_empty(): break
	if site.is_empty():
		push_error("No Mile End station found for seed %d" % world_seed)
		get_tree().quit(1)
		return
	var band := floori(float(site.s) / field.profile.chunk_length)
	$WorldGenerator.world_seed = world_seed
	$WorldGenerator.profile = field.profile
	$WorldGenerator.restore_bands.assign(range(band - 1, band + 2))
	$Player.transform = site.building * Transform3D(Basis(Vector3.UP, 0.25), Vector3(4, 0.25, 13))
	$NewRv/Chassis.transform = site.building * Transform3D(Basis(Vector3.UP, PI/2), Vector3(12, 1.65, 14))

func _ready() -> void:
	if site.is_empty(): return
	$WorldClock.set_time(1, 14.0)
	$NewRv/Chassis.handbrake = true
	get_window().title = "Mile End Motor Fuel | seed %d" % world_seed
	print("MILE_END_READY seed=", world_seed, " site=", site.id)
	if "--capture" in OS.get_cmdline_user_args():
		var camera := Camera3D.new()
		add_child(camera)
		camera.cull_mask = get_viewport().get_camera_3d().cull_mask
		camera.current = true
		await _capture(camera, Vector3(-8, 1.75, 16), Vector3(0, 2.15, 0), "approach")
		await _capture(camera, Vector3(-9, 6.5, 15), Vector3(0, 1.8, 0), "yard")
		await _capture(camera, Vector3(-1.7, 1.72, -0.7), Vector3(1.25, 1.1, -6.8), "shop")
		var pump := $WorldGenerator.find_child("Dispenser", true, false) as CollisionShape3D
		if pump != null:
			var center: Vector3 = site.building.affine_inverse() * pump.global_position
			await _capture(camera, center + Vector3(1.1, 0.9, 2.15), center + Vector3.UP * 0.15, "pump")
		get_tree().quit()

func _capture(camera: Camera3D, at: Vector3, target: Vector3, label: String) -> void:
	camera.position = site.building * at
	camera.look_at(site.building * target)
	# At initial load the streaming veil lifts gradually as finished chunks arrive.
	var deadline := Time.get_ticks_msec() + 30000
	var weather_limit: float = $WorldClock.atmosphere.mist($WorldClock.effective_visual_weather(), $WorldClock.haze_dust).depth_end
	while $WorldClock.environment.fog_depth_end < minf(110.0, weather_limit - 1.0) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "res://.godot/mile-end-%d-%s.png" % [world_seed, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE: ", path)
