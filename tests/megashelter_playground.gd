extends Node3D
## Exterior authoring and actual wheel-powered parking. Outputs stay in .godot/.
var seed_value := 42
var template_index := 1
var plan: Dictionary
var building: Node3D
var camera: Camera3D
var player: Node3D
var vehicle: Chassis
var clock: WorldClock
var label: Label
var kit_root: Node3D
var weather_index := 0
var driving := false
var build_ms := 0.0
var frame_samples: Array[float] = []
var review_torch: Flashlight

func _ready() -> void:
	get_window().title = "ApocalypseRV - Modular Megashelter"
	get_window().size = Vector2i(1280, 800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = arg.trim_prefix("--seed=").to_int()
		if arg.begins_with("--template="): template_index = clampi(arg.trim_prefix("--template=").to_int(), 0, 2)
	var holder := WorldEnvironment.new()
	holder.name = "WorldEnvironment"
	holder.environment = Environment.new()
	add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	add_child(sun)
	clock = WorldClock.new()
	clock.name = "WorldClock"
	clock.running = false
	clock.weather_running = false
	add_child(clock)
	clock.set_time(1, 14.0)
	clock.weather.set_weather(Vector3(0, 0, 0), true)
	add_child.call_deferred(OutdoorPresentation.new())
	var adaptation := NightVisionEffect.new()
	adaptation.name = "DarkAdaptation"
	add_child.call_deferred(adaptation)
	_ground()
	_forest()
	_rebuild()
	player = preload("res://player/player.tscn").instantiate()
	player.position = plan.access_point + Vector3(7, 0.5, 3)
	add_child(player)
	var rv := preload("res://rv/starter_rv.tscn").instantiate()
	rv.position = Vector3(-10, 1.5, float(plan.depth) * 0.5 + 22)
	add_child(rv)
	vehicle = rv.get_node("Chassis")
	vehicle.handbrake = true
	camera = Camera3D.new()
	camera.far = 400
	camera.fov = 68
	add_child(camera)
	review_torch = preload("res://props/flashlight.tscn").instantiate()
	review_torch.freeze = true
	review_torch.collision_layer = 0
	review_torch.collision_mask = 0
	review_torch.rotation_degrees.x = -90
	review_torch.position = Vector3(0.2, -0.2, -0.3)
	camera.add_child(review_torch)
	review_torch.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	label = Label.new()
	label.position = Vector2(18, 185)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(label)
	_overview()
	_status()
	print("MEGASHELTER_READY seed=%d template=%d modules=%d build_ms=%.2f" % [seed_value, template_index, plan.modules.size(), build_ms])
	if "--capture" in OS.get_cmdline_user_args(): _capture_set()
	elif "--benchmark" in OS.get_cmdline_user_args(): _benchmark()
	elif "--replay" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.0).timeout
		_drive()

func _process(delta: float) -> void:
	if frame_samples.size() < 360: frame_samples.append(delta * 1000.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or driving: return
	match event.keycode:
		KEY_F2: _overview()
		KEY_F3: _entrance()
		KEY_F4:
			kit_root_visible(false)
			(player.get("camera") as Camera3D).make_current()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		KEY_F5:
			template_index = (template_index + 1) % 3
			_rebuild()
			_overview()
			_status()
		KEY_F6:
			seed_value += 1
			_rebuild()
			_overview()
			_status()
		KEY_F7:
			weather_index = (weather_index + 1) % 3
			clock.set_time(1, 22.0 if weather_index == 2 else 14.0)
			clock.weather.set_weather(Vector3(1 if weather_index == 0 else 0, 0, 0.5 if weather_index == 1 else 0), true)
			review_torch.switched_on = weather_index == 2
			review_torch.visible = weather_index == 2
			review_torch.set_held_active(weather_index == 2)
		KEY_F8: _kit_view()
		KEY_F9: _capture("manual")
		KEY_F10: _drive()

func _rebuild() -> void:
	if is_instance_valid(building):
		remove_child(building)
		building.free()
	plan = MegashelterPlan.generate(seed_value, template_index)
	var start := Time.get_ticks_usec()
	building = POIConfig.instantiate_site({"definition_id": "modular_megashelter", "seed": seed_value, "exterior_plan": plan})
	add_child(building)
	build_ms = float(Time.get_ticks_usec() - start) / 1000.0
	frame_samples.clear()
	if is_instance_valid(player): player.position = plan.access_point + Vector3(7, 0.5, 3)

func _overview() -> void:
	kit_root_visible(false)
	camera.position = Vector3(float(plan.width) * 0.95, 13, float(plan.depth) * 0.5 + float(plan.height) * 1.25)
	camera.fov = 68
	camera.look_at(Vector3(0, float(plan.height) * 0.44, 0))
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _entrance() -> void:
	kit_root_visible(false)
	camera.position = Vector3(16, 3.1, float(plan.depth) * 0.5 + 24)
	camera.fov = 68
	camera.look_at(Vector3(0, 4.2, float(plan.depth) * 0.5))
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func kit_root_visible(value: bool) -> void:
	if is_instance_valid(kit_root): kit_root.visible = value
	if is_instance_valid(building): building.visible = not value

func _kit_view() -> void:
	if not is_instance_valid(kit_root):
		kit_root = Node3D.new()
		add_child(kit_root)
		var sizes := [Vector3(4,4.5,0.4), Vector3(4,4.5,0.4), Vector3(1,4.5,1), Vector3(1.25,4.5,0.85), Vector3(4,0.6,0.75), Vector3(4,4.5,0.4), Vector3(12,9,3), Vector3(4,0.35,4)]
		for index in range(8):
			var origin := Vector3((index % 4) * 15 - 23, 0, 74 + (index / 4) * 16)
			for piece: Dictionary in MegashelterKit.pieces(MegashelterPlan.KINDS[index], sizes[index]):
				var mesh := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = piece.size
				mesh.mesh = box
				mesh.position = origin + piece.center
				mesh.material_override = building.get_node("Visuals").get_child(piece.material).mesh.surface_get_material(0)
				kit_root.add_child(mesh)
	kit_root_visible(true)
	camera.fov = 85
	camera.position = Vector3(24, 18, 112)
	camera.look_at(Vector3(0, 2, 81))
	camera.make_current()

func _ground() -> void:
	var body := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500, 1, 500)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	ground.mesh = plane
	ground.material_override = IndustrialArt.material("concrete", Color("585e52"))
	add_child(ground)

func _forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7032
	var trees: Array = []
	var brush: Array = []
	for index in range(110):
		var angle := rng.randf_range(-PI, PI)
		var distance := rng.randf_range(70, 190)
		var point := Vector3(sin(angle) * distance, 0, cos(angle) * distance)
		if point.z > 45 and absf(point.x) < 65: continue
		trees.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(3.0, rng.randf_range(12,21),3.0)), point))
	for index in range(60):
		var point := Vector3(rng.randf_range(-70,70), 0, rng.randf_range(-50,65))
		if absf(point.x) < 36 and point.z < 55: continue
		brush.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(0.7,1.5)), point))
	ForestScenery.batch(self, "ReviewTrees", ForestMeshes.tree(0), trees)
	ForestScenery.batch(self, "ReviewBrush", FloraMeshes.ground(0), brush)

func _status() -> void:
	label.text = "MEGASHELTER / seed %d / %s / %.0f x %.0f x %.1f m\nF2 exterior  F3 entrance  F4 walk  F5 shape  F6 seed\nF7 weather/time  F8 kit  F9 capture  F10 parking replay" % [seed_value, ["Slab", "Central tower", "Stepped"][template_index], plan.width, plan.depth, plan.height]

func _capture(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://.godot/megashelter-%d-%d-%s.png" % [seed_value, template_index, suffix]
	get_viewport().get_texture().get_image().save_png(path)
	print("MEGASHELTER_CAPTURE ", path)

func _capture_set() -> void:
	label.visible = false
	await get_tree().create_timer(1.5).timeout
	for index in range(3):
		template_index = index
		_rebuild()
		_overview()
		await get_tree().create_timer(0.5).timeout
		await _capture("exterior")
	_entrance()
	await get_tree().create_timer(0.4).timeout
	await _capture("entrance")
	_kit_view()
	await get_tree().create_timer(0.4).timeout
	await _capture("kit")
	kit_root_visible(false)
	for weather in range(3):
		clock.set_time(1, 22 if weather == 2 else 14)
		clock.weather.set_weather(Vector3(1 if weather == 0 else 0, 0, 0.5 if weather == 1 else 0), true)
		_entrance()
		if weather == 2:
			camera.position = Vector3(7, 1.8, float(plan.depth) * 0.5 + 13)
			camera.look_at(Vector3(0, 3.0, float(plan.depth) * 0.5))
			review_torch.visible = true
			review_torch.switched_on = true
			review_torch.set_held_active(true)
		await get_tree().create_timer(0.5).timeout
		await _capture(["day", "overcast", "night"][weather])
	label.visible = true
	print("MEGASHELTER_RENDER_COMPLETE build_ms=", build_ms)
	if "--quit-after-review" in OS.get_cmdline_user_args(): get_tree().quit()

func _benchmark() -> void:
	await get_tree().create_timer(2.0).timeout
	var results := {"seed": seed_value, "template": template_index, "build_ms": build_ms,
		"renderer": RenderingServer.get_current_rendering_method(), "viewport": get_viewport().get_visible_rect().size,
		"gpu": RenderingServer.get_video_adapter_name(), "samples": 180}
	for visible_geometry: bool in [false, true]:
		building.visible = visible_geometry
		await get_tree().create_timer(0.5).timeout
		var frames: Array[float] = []
		for frame in range(180):
			var start := Time.get_ticks_usec()
			await get_tree().process_frame
			frames.append(float(Time.get_ticks_usec() - start) / 1000.0)
		frames.sort()
		results["with_building" if visible_geometry else "without_building"] = {"median_ms": frames[90], "p95_ms": frames[171],
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	var triangles := 0
	for mesh: MeshInstance3D in building.get_node("Visuals").get_children():
		triangles += mesh.mesh.surface_get_array_index_len(0) / 3
	results["building_triangles"] = triangles
	var file := FileAccess.open("res://.godot/megashelter-benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	print("MEGASHELTER_BENCHMARK ", JSON.stringify(results))
	if "--quit-after-review" in OS.get_cmdline_user_args(): get_tree().quit()

func _drive() -> void:
	if driving: return
	driving = true
	vehicle.allow_test_controls = true
	vehicle.current_fuel = 100
	vehicle.set_engine_running(true)
	vehicle.handbrake = false
	_overview()
	var parked := await _drive_leg(false, float(plan.depth) * 0.5 + 13)
	vehicle.control_override = {"throttle": 0.0, "brake": 1.0, "steering": 0.0}
	for frame in range(90): await get_tree().physics_frame
	var departed := false
	if parked: departed = await _drive_leg(true, float(plan.depth) * 0.5 + 35)
	vehicle.control_override = {}
	vehicle.handbrake = true
	driving = false
	label.text = "PASS: real-wheel parking and reverse departure" if parked and departed else "FAIL: parking replay"
	print("PASS: megashelter real-wheel approach, parking and reverse departure" if parked and departed else "FAIL: megashelter parking replay")
	print("MEGASHELTER_DRIVE parked=", parked, " departed=", departed, " position=", vehicle.global_position)
	if "--quit-after-review" in OS.get_cmdline_user_args(): get_tree().quit(0 if parked and departed else 1)

func _drive_leg(reverse: bool, target_z: float) -> bool:
	vehicle.gear = -1 if reverse else 4
	for frame in range(1800):
		var remaining := target_z - vehicle.global_position.z if reverse else vehicle.global_position.z - target_z
		if remaining < 1.5: return true
		var speed := vehicle.linear_velocity.length()
		var local := vehicle.global_transform.affine_inverse() * Vector3(-10, 0, target_z)
		var angle := atan2(local.x, local.z) if reverse else atan2(-local.x, -local.z)
		var steering := clampf(angle * (-1.8 if reverse else 1.8) / vehicle.max_steering, -1, 1)
		vehicle.control_override = {"throttle": clampf((2.5 - speed) * 0.7, 0, 1), "brake": clampf((speed - 3) * 0.5, 0, 1), "steering": steering}
		label.text = "PARKING REPLAY / %s / %.1f m / %.1f m/s" % ["depart" if reverse else "approach", remaining, speed]
		await get_tree().physics_frame
	return false
