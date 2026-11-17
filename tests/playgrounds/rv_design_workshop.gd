extends Node3D
## Production assets, optional wheel-driven demonstration, no changes to game input.
var rv: Chassis
var seat: Item
var player: CharacterBody3D
var observer: Camera3D
var view := 0
var demonstration := false
var legacy: Node3D
var instructions: Label

func _ready() -> void:
	get_window().title = "ApocalypseRV - RV Design Workshop"
	set_meta("entity_domain", true)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.17, 0.23, 0.26)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.78, 0.85, 0.90)
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 0.2, 400)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.1
	var mesh := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = box.size
	mesh.mesh = ground_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.17, 0.19, 0.19)
	mesh.material_override = material
	ground.add_child(mesh)
	add_child(ground)
	for i in range(-30, 31):
		var marking := MeshInstance3D.new()
		var stripe := BoxMesh.new()
		stripe.size = Vector3(0.12, 0.012, 2.0)
		marking.mesh = stripe
		marking.material_override = load("res://rv/visuals/cream.tres")
		marking.position = Vector3(4.0, 0.012, float(i) * 5.0)
		add_child(marking)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 1.6
	add_child(shell)
	rv = shell.get_node("Chassis")
	rv.allow_test_controls = true
	seat = rv.get_node("DriverSeat")
	rv.current_fuel = 65
	rv.current_power = 72
	player = load("res://player/player.tscn").instantiate()
	player.position = Vector3(6, 1, 6)
	add_child(player)
	player.set_physics_process(false)
	observer = Camera3D.new()
	observer.fov = 62
	add_child(observer)
	observer.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	instructions = Label.new()
	instructions.position = Vector2(24, 100)
	instructions.add_theme_font_size_override("font_size", 24)
	instructions.add_theme_color_override("font_shadow_color", Color.BLACK)
	instructions.add_theme_constant_override("shadow_offset_x", 2)
	instructions.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(instructions)
	if "--capture" in OS.get_cmdline_user_args():
		canvas.visible = false
		_capture.call_deferred()

## Renders the real seat view, a dashboard close-up and a raking side view for fixed
## vehicle states, then quits.
func _capture() -> void:
	var folder := "res://.godot/rv-workshop-captures"
	DirAccess.make_dir_recursive_absolute(folder)
	var sun: DirectionalLight3D
	var sky: Environment
	for node in get_children():
		if node is DirectionalLight3D: sun = node
		if node is WorldEnvironment: sky = node.environment
	var day_sun := sun.light_energy
	var day_ambient := sky.ambient_light_energy
	var visual: Node3D = seat.get_node("CockpitVisual")
	var cluster: Node3D = visual.get_node("InstrumentCluster")
	for state in ["day_drive", "night_faults", "unpowered", "lamp_test"]:
		visual.set_process(true)
		seat.exit_seat()
		rv.control_override = {}
		rv.linear_velocity = Vector3.ZERO
		rv.current_fuel = rv.max_fuel * 0.65
		rv.current_power = rv.max_power * 0.72
		rv.headlights_requested = false
		rv.handbrake = true
		rv.set_gear(0)
		rv.set_engine_running(false)
		sun.light_energy = day_sun
		sky.ambient_light_energy = day_ambient
		seat.interact_hold(player)
		match state:
			"day_drive":
				rv.set_engine_running(true)
				rv.set_gear(2)
				rv.handbrake = false
				rv.control_override = {"throttle": 0.7}
			"night_faults":
				sun.light_energy = 0.02
				sky.ambient_light_energy = 0.06
				rv.current_fuel = rv.max_fuel * 0.08
				rv.current_power = rv.max_power * 0.15
				rv.headlights_requested = true
				rv.set_engine_running(true)
			"unpowered":
				rv.current_power = 0.0
			"lamp_test":
				rv.set_engine_running(true)
		await get_tree().create_timer(4.0).timeout
		if state == "lamp_test":
			# Hold every lamp on, cycling the three severities, to judge symbol legibility.
			visual.set_process(false)
			for i in range(VehicleStatus.IDS.size()):
				cluster.light_lamp(cluster.warning_lamps[VehicleStatus.IDS[i]], cluster.lamp_color(1 + i % 3), rv.instrument_brightness)
		for shot in ["seat", "close", "angle"]:
			var camera: Camera3D = seat.seat_camera
			if shot != "seat":
				view = 5 if shot == "close" else 6
				observer.cull_mask = camera.cull_mask
				observer.fov = 52
				observer.current = true
			else:
				camera.current = true
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var path := "%s/%s_%s.png" % [folder, state, shot]
			get_viewport().get_texture().get_image().save_png(path)
			print("CAPTURE: ", ProjectSettings.globalize_path(path))
	print("PASS: RV workshop captures")
	get_tree().quit()

func _process(_delta: float) -> void:
	if view == 0:
		observer.global_position = rv.to_global(Vector3(11, 6, -13))
		observer.look_at(rv.to_global(Vector3(0, 1, 0)))
	elif view == 1:
		observer.global_position = rv.to_global(Vector3(0.45, 2.05, 4.7))
		observer.look_at(rv.to_global(Vector3(0, 1.3, -4.5)))
	elif view == 4:
		observer.global_position = rv.to_global(Vector3(0.85, 2.05, -2.9))
		observer.look_at(seat.to_global(Vector3(0, 0.65, -0.55)))
	elif view == 5:
		var cluster: Node3D = seat.get_node("CockpitVisual/InstrumentCluster")
		observer.global_position = seat.seat_camera.global_position.lerp(cluster.global_position, 0.3)
		observer.look_at(cluster.global_position)
	elif view == 6:
		var cluster: Node3D = seat.get_node("CockpitVisual/InstrumentCluster")
		observer.global_position = cluster.to_global(Vector3(0.75, 0.3, 0.62))
		observer.look_at(cluster.global_position)
	elif view == 3:
		observer.global_position = legacy.get_node("Chassis").to_global(Vector3(11, 6, -13))
		observer.look_at(legacy.get_node("Chassis").to_global(Vector3(0, 1, 0)))
	instructions.text = "WAYFARER / RV DESIGN WORKSHOP\nF2 Exterior · F3 Interior · F4 Driver Seat · F5 Wheel-Drive Demo · F6 Legacy Comparison · F7 Full Dashboard\n%s | %.1f km/h | FUEL %.1f | BATTERY %.1f" % ["Driving" if demonstration else "Parked", rv.linear_velocity.length() * 3.6, rv.current_fuel, rv.current_power]

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F2, KEY_F3:
			_stop_demo()
			view = 0 if event.keycode == KEY_F2 else 1
			observer.current = true
		KEY_F4:
			_stop_demo()
			view = 2
			seat.interact_hold(player)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		KEY_F5:
			view = 2
			if not is_instance_valid(seat.current_driver): seat.interact_hold(player)
			demonstration = not demonstration
			rv.set_engine_running(demonstration)
			rv.set_gear(1)
			rv.handbrake = not demonstration
			rv.control_override = {"throttle": 0.45, "steering": 0.15} if demonstration else {}
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		KEY_F7:
			_stop_demo()
			view = 4
			observer.current = true
		KEY_F6:
			_stop_demo()
			if not is_instance_valid(legacy):
				legacy = load("res://rv/legacy/new_rv.tscn").instantiate()
				legacy.position = Vector3(24, 1.6, 0)
				add_child(legacy)
			view = 3
			observer.current = true

func _stop_demo() -> void:
	demonstration = false
	rv.control_override = {}
	rv.handbrake = true
	rv.set_engine_running(false)
	seat.exit_seat()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
