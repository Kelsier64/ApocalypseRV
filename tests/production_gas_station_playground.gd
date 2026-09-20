extends "res://world/test_world.gd"
## Visual QA using the real main scene, terrain, station and wheel physics.
var site: Dictionary
var observer: Camera3D
var status: Label
var driving := false

func _enter_tree() -> void:
	super._enter_tree()
	var profile := WorldProfile.new()
	var field := WorldField.new(42, profile)
	site = field.stop(1)
	$WorldGenerator.world_seed = 42
	$WorldGenerator.profile = profile
	var band := floori(float(site.s) / 150)
	for index in range(band - 2, band + 4): $WorldGenerator.restore_bands.append(index)
	$Player.position = site.building * Vector3(0, 0.3, 21)
	$NewRv/Chassis.transform = field.road_frame(float(site.s) - 35)
	$NewRv/Chassis.position.y += 1.8

func _ready() -> void:
	super._ready()
	await wait_for_play()
	for monster in get_tree().get_nodes_in_group(Groups.MONSTERS): monster.queue_free()
	get_window().title = "ApocalypseRV - Production Gas Station"
	get_window().size = Vector2i(1280, 800)
	observer = Camera3D.new()
	observer.far = 500
	add_child(observer)
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(20, 110)
	status.add_theme_font_size_override("font_size", 20)
	layer.add_child(status)
	status.text = "PRODUCTION WORLD v5 / NORTHLINE\nF2 site overview / F3 walk / F5 wheel-driven parking replay / F7 capture"
	_view()
	print("PRODUCTION_STATION_READY at=",site.building.origin)
	if "--replay" in OS.get_cmdline_user_args(): _drive()

func _unhandled_key_input(event: InputEvent) -> void:
	if observer == null or driving or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F2: _view()
		KEY_F3:
			$Player.camera.make_current()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		KEY_F5: _drive()
		KEY_F7: _capture()

func _view() -> void:
	observer.position = site.building * Vector3(35, 24, 45)
	observer.look_at(site.building * Vector3(0, 1, 0))
	observer.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/production-station.png")

func _drive() -> void:
	driving = true
	var vehicle: Chassis = $NewRv/Chassis
	vehicle.allow_test_controls = true
	vehicle.current_fuel = 100
	vehicle.set_engine_running(true)
	vehicle.handbrake = false
	vehicle.gear = 4
	$NewRv/Chassis/DriverSeat.interact_hold($Player)
	observer.make_current()
	var points: Array[Vector3] = []
	for p in [Vector3(8,0,14), Vector3(23,0,3), Vector3(33,0,-4)]:
		p.x *= float(site.side)
		points.append(site.road * p)
	var leg := 0
	for frame in range(2400):
		var target := points[leg]
		var horizontal := vehicle.global_position - target
		horizontal.y = 0
		if horizontal.length() < 2.5:
			leg += 1
			if leg == points.size(): break
			target = points[leg]
		var local := vehicle.global_transform.affine_inverse() * target
		var angle := atan2(-local.x, -local.z)
		var speed := vehicle.linear_velocity.length()
		var steering_limit := lerpf(vehicle.max_steering, vehicle.max_steering * 0.3, clampf(speed / vehicle.max_speed, 0, 1))
		vehicle.control_override = {"throttle": clampf((4.0 - speed) * 0.6, 0, 1), "brake": clampf((speed - 5.0) * 0.3, 0, 1), "steering": clampf(angle * 1.8 / steering_limit, -1, 1)}
		status.text = "PARKING / approach %d of 3 / %.1f m/s" % [leg + 1, speed]
		await get_tree().physics_frame
	vehicle.control_override = {}
	vehicle.handbrake = true
	for frame in range(120): await get_tree().physics_frame
	$NewRv/Chassis/DriverSeat.exit_seat()
	driving = false
	status.text = ("PASS: highway to station parking using real wheels" if leg == points.size() else "FAIL: parking route blocked") + "\nF3 walk and explore / E loot / F2 overview / F7 capture"
	print(status.text)
