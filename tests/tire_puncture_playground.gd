extends Node3D
var rv: Chassis
var camera: Camera3D
var label: Label
var running := false
var elapsed := 0.0
var ready_to_drive := false

func _ready() -> void:
	get_window().title = "ApocalypseRV - Tire Puncture"
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 0.2, 300)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.1
	add_child(ground)
	RoadsideKit.part(self, box.size, ground.position, Color("4b504a"))
	for z in range(-140, 100, 5):
		RoadsideKit.part(self, Vector3(0.12, 0.02, 2.5), Vector3(0, 0.01, z), Color("c8ba83"))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("667781")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 1.8
	add_child(shell)
	rv = shell.get_node("Chassis")
	rv.allow_test_controls = true
	var hazard := TireSpikeStrip.new()
	add_child(hazard)
	hazard.position = Vector3(1.5, 0.02, -14)
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(label)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for i in range(90): await get_tree().physics_frame
	ready_to_drive = true
	if "--replay" in OS.get_cmdline_user_args(): start()

func start() -> void:
	if not ready_to_drive: return
	running = true
	elapsed = 0
	rv.set_engine_running(true)
	rv.gear = 2
	rv.handbrake = false

func _physics_process(delta: float) -> void:
	if not is_instance_valid(rv): return
	if running:
		elapsed += delta
		rv.control_override = {"throttle": 1.0} if elapsed < 7 else {"brake": 1.0}
		if elapsed > 10:
			running = false
			rv.handbrake = true
			print("TIRE_REPLAY hp=%s position=%s" % [rv.wheel_health, rv.global_position])
	else:
		rv.control_override = {"throttle": Input.get_action_strength("move_forward"), "brake": Input.get_action_strength("move_back"), "steering": Input.get_action_strength("move_left") - Input.get_action_strength("move_right")}

func _process(_delta: float) -> void:
	if not is_instance_valid(rv): return
	camera.global_position = rv.global_position + Vector3(11, 6, -14)
	camera.look_at(rv.global_position + Vector3(0, 0, -3))
	label.text = "爆胎測試｜F6 自動行駛壓釘帶｜1–4 個別爆胎｜R 重設\nW/S 油門煞車 · A/D 修正 · Space 手煞車 · Z 倒車 · X 前進\n%.0f km/h｜%s\n左前 %.0f　右前 %.0f　左後 %.0f　右後 %.0f" % [rv.road_speed() * 3.6, rv.tire_warning(), rv.wheel_health[0], rv.wheel_health[1], rv.wheel_health[2], rv.wheel_health[3]]

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode >= KEY_1 and event.keycode <= KEY_4: rv.puncture_wheel(event.keycode - KEY_1)
	match event.keycode:
		KEY_F6: start()
		KEY_R: get_tree().reload_current_scene()
		KEY_SPACE:
			rv.set_engine_running(true)
			rv.handbrake = not rv.handbrake
		KEY_Z: rv.gear = -1
		KEY_X: rv.gear = 2
