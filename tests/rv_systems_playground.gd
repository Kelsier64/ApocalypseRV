extends Node3D
var rv: Chassis
var player: CharacterBody3D
var tablet: Equipment
var status: Label
var observer: Camera3D
var station: CraftingStation
var generator: Equipment
var original_charge: float
var telemetry_time := 0.0
var seconds := 0.0
var replay := false
var stage := -1

func _ready() -> void:
	set_meta("entity_domain", true)
	get_window().title = "ApocalypseRV - RV Systems Validation"
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(250, 0.2, 250)
	shape.shape = box
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = box.size
	mesh.mesh = visual
	ground.add_child(mesh)
	add_child(ground)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.22, 0.3)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var vehicle: Node3D = load("res://rv/new_rv.tscn").instantiate()
	vehicle.position.y = 1.8
	add_child(vehicle)
	rv = vehicle.get_node("Chassis")
	rv.contact_monitor = true
	rv.max_contacts_reported = 32
	player = load("res://player/player.tscn").instantiate()
	player.position = Vector3(7, 1, 0)
	add_child(player)
	generator = _mount("res://equipment/generator.tscn", Vector3(0.8, 0.7, 0))
	station = _mount("res://equipment/crafting_station.tscn", Vector3(-0.8, 0.6, 1.8))
	tablet = _mount("res://equipment/tablet_screen.tscn", Vector3(0.8, 1.0, -2))
	_mount("res://equipment/scrapper.tscn", Vector3(-0.8, 0.6, -1.5))
	rv.current_power = 20.0
	rv.add_item(ItemNames.METAL_PARTS, 20)
	rv.add_item(ItemNames.UNREFINED_FUEL, 20)
	var battery: Prop = load("res://props/battery.tscn").instantiate()
	add_child(battery)
	battery.battery.charge = 75.0
	player.add_prop_item(battery, battery.scene_file_path)
	battery.queue_free()
	observer = Camera3D.new()
	add_child(observer)
	observer.position = Vector3(12, 10, 15)
	observer.look_at(rv.position + Vector3.UP)
	observer.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	status = Label.new()
	status.position = Vector2(24, 24)
	status.add_theme_font_size_override("font_size", 22)
	layer.add_child(status)
	replay = "--replay" in OS.get_cmdline_user_args()

func _mount(path: String, local_position: Vector3) -> Equipment:
	var device: Equipment = load(path).instantiate()
	add_child(device)
	device.confirm_placement(rv.global_transform * Transform3D(Basis.IDENTITY, local_position), rv, rv)
	return device

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F2: rv.set_engine_running(not rv.energy.engine_running)
		KEY_F3: rv.exchange_battery(player)
		KEY_F4:
			rv.get_node("DriverSeat").interact_hold(player)
		KEY_F5: tablet.interact_hold(player)
		KEY_F6:
			replay = true
			seconds = 0.0
			stage = -1
		KEY_F7:
			tablet.take_damage(1000)
		KEY_R:
			if not player.in_ui_mode and player.seated_in == null: get_tree().reload_current_scene()

func _physics_process(delta: float) -> void:
	telemetry_time += delta
	if telemetry_time >= 5.0:
		telemetry_time = 0.0
		print("RV PHYSICS position=", rv.global_position, " velocity=", rv.linear_velocity, " center=", rv.center_of_mass, " contacts=", rv.get_colliding_bodies().map(func(n): return n.name))
	status.visible = not player.in_ui_mode and player.seated_in == null
	status.text = "RV SYSTEMS | engine %s | fuel %.2f | battery %.2f / %.0f\nGeneration %.2f / load %.2f | mass %.0f | stage %d\nF2 engine | F3 swap battery | F4 seat | F5 tablet | F6 replay | F7 destroy tablet" % [
		"ON" if rv.energy.engine_running else "OFF", rv.current_fuel, rv.current_power, rv.max_power,
		rv.energy.generated_rate, rv.energy.load_rate, rv.mass, stage]
	if not replay: return
	seconds += delta
	var next := int(seconds / 5.0)
	if next != stage:
		stage = next
		match stage:
			0:
				rv.set_engine_running(false)
				original_charge = rv.current_power
			1:
				print("REPLAY parked battery drain: ", rv.current_power < original_charge)
				rv.set_engine_running(true)
				original_charge = rv.current_power
			2:
				print("REPLAY stationary charging: ", rv.current_power > original_charge)
				rv.exchange_battery(player)
				print("REPLAY swapped battery: ", rv.current_power)
				station.request_craft("gasoline")
			3:
				print("REPLAY craft complete: ", station.jobs.is_empty())
				rv.handbrake = false
				rv.allow_test_controls = true
				rv.control_override = {"throttle": 0.35, "steering": 0.25}
			4:
				rv.control_override = {"throttle": 0.35, "steering": -0.25}
			5:
				rv.control_override = {}
				rv.handbrake = true
				rv.set_engine_running(false)
				print("REPLAY wheel-driven speed: ", rv.linear_velocity.length())
			6:
				replay = false
				print("PASS: RV systems visible replay completed")
	observer.position = rv.global_position + Vector3(12, 10, 15)
	observer.look_at(rv.global_position + Vector3.UP)
