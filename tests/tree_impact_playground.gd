extends Node3D
## Visible wheel-driven replay using the production chassis and batched forest.
var rv: Chassis
var chunk: ChunkGenerator
var camera: Camera3D
var label: Label
var running := false
var elapsed := 0.0
var ready_to_drive := false
var health_before := 0.0
var impact_reported := false
var impact_elapsed := -1.0
static var chain_requested := false
var chain_mode := false
var minimum_chain_speed := INF
var chain_reported := false

func _ready() -> void:
	chain_mode = chain_requested or "--chain" in OS.get_cmdline_user_args()
	get_window().title = "ApocalypseRV - Tree Impact"
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 0.2, 200)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.1
	add_child(ground)
	RoadsideKit.part(self, box.size, ground.position, Color("4b504a"))
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
	chunk = ChunkGenerator.new()
	chunk.field = WorldField.new(42)
	var planned: Array[Dictionary] = [{"point": Vector3(0, 0, -35), "height": 14.0, "width": 3.0, "angle": 0.0}, {"point": Vector3(10, 0, -35), "height": 15.0, "width": 3.0, "angle": 0.5}]
	if chain_mode:
		planned.clear()
		for row in range(8):
			for x in [-0.8, 0.8]:
				planned.append({"point": Vector3(x, 0, -13.0 - row * 6.0), "height": 14.0, "width": 3.0, "angle": 0.0})
	chunk.field.forest_cache = {0: planned, -1: [] as Array[Dictionary], 1: [] as Array[Dictionary]}
	add_child(chunk)
	await ForestScenery.build(chunk, false)
	# Keep the two trunks/canopies unobstructed for inspection.
	for node in chunk.get_children():
		if str(node.name).begins_with("ForestBrush"): node.hide()
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 1.8
	add_child(shell)
	rv = shell.get_node("Chassis")
	rv.allow_test_controls = true
	health_before = rv.get_engine().health
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
	if chain_mode or "--replay" in OS.get_cmdline_user_args(): start()

func start() -> void:
	if not ready_to_drive or impact_reported: return
	running = true
	elapsed = 0
	rv.set_engine_running(true)
	rv.gear = 2
	rv.handbrake = false
	if chain_mode: rv.linear_velocity = Vector3.FORWARD * 8.0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(rv): return
	if running:
		elapsed += delta
		var destroyed := not chunk.field.destroyed_trees.is_empty()
		# Continue on real wheel power for two seconds past impact, then brake.
		var continue_driving := elapsed < 12 and (impact_elapsed < 0 or elapsed < impact_elapsed + 2.0)
		if chain_mode:
			continue_driving = elapsed < 30 and rv.global_position.z > -65.0
			var speed := rv.linear_velocity.dot(Vector3.FORWARD)
			rv.control_override = {"throttle": clampf(0.5 + (8.0 - speed) * 0.5, 0.0, 1.0), "steering": clampf(rv.global_position.x * 0.12 + rv.rotation.y * 0.8, -0.25, 0.25)} if continue_driving else {"brake": 1.0}
			if destroyed and continue_driving: minimum_chain_speed = minf(minimum_chain_speed, speed)
			if not continue_driving and not chain_reported:
				chain_reported = true
				print("TREE_CHAIN_REPLAY destroyed=%d min_speed=%.2f speed=%.2f distance=%.2f engine=%.2f seconds=%.2f" % [chunk.field.destroyed_trees.size(), minimum_chain_speed, speed, -rv.global_position.z, rv.get_engine().health, elapsed])
		else:
			rv.control_override = {"throttle": 1.0} if continue_driving else {"brake": 1.0}
		if destroyed and not impact_reported:
			impact_reported = true
			impact_elapsed = elapsed
			print("TREE_REPLAY destroyed=%d engine=%.2f before=%.2f speed=%.2f position=%s" % [chunk.field.destroyed_trees.size(), rv.get_engine().health, health_before, rv.linear_velocity.length(), rv.global_position])
			if not chain_mode: _report_visual.call_deferred()
		if elapsed > (33 if chain_mode else 15):
			running = false
			rv.handbrake = true
	else:
		rv.control_override = {"throttle": Input.get_action_strength("move_forward"), "brake": Input.get_action_strength("move_back"), "steering": Input.get_action_strength("move_left") - Input.get_action_strength("move_right")}

func _report_visual() -> void:
	var body := chunk.get_node("ForestTrunks") as ForestTrunks
	var entry: Dictionary = body.visuals[Vector3(0, 0, -35)]
	var hidden: bool = entry.node.multimesh.get_instance_transform(entry.index).basis == Basis.from_scale(Vector3.ZERO)
	print("TREE_VISUAL hidden=%s neighbour_solid=%s" % [hidden, not body.get_child(1).disabled])

func _process(_delta: float) -> void:
	if not is_instance_valid(rv) or camera == null: return
	camera.global_position = Vector3(25, 13, rv.global_position.z + 18) if chain_mode else Vector3(25, 13, -7)
	camera.look_at(Vector3(0, 4, rv.global_position.z - 10) if chain_mode else Vector3(0, 5, -30))
	label.text = "撞樹測試｜F6 單樹 · F7 連續撞樹｜R 重設\nW/S 油門煞車 · A/D 轉向 · Space 手煞車\n%.0f km/h｜引擎耐久 %.0f → %.0f\n撞毀 %d / %d 棵" % [rv.road_speed() * 3.6, health_before, rv.get_engine().health, chunk.field.destroyed_trees.size(), 16 if chain_mode else 1]
	if chain_mode: label.text += "｜連撞最低 %.1f km/h" % (minimum_chain_speed * 3.6 if is_finite(minimum_chain_speed) else 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F6: start()
		KEY_F7:
			chain_requested = true
			get_tree().reload_current_scene()
		KEY_R: get_tree().reload_current_scene()
		KEY_SPACE:
			rv.set_engine_running(true)
			rv.handbrake = not rv.handbrake
