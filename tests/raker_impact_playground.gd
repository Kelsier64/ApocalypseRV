extends Node3D
## Real wheel-driven frontal/offset contact with the production Raker and RV.
const CASES := ["目標 36 km/h · 存活起身", "目標 61 km/h · 受傷目標 40 HP", "目標 36 km/h · 偏側撞擊", "目標 14 km/h · 輕撞擊退"]
const SPEEDS := [10.0, 17.0, 10.0, 4.0]
static var selected := 0
static var read_args := false
var rv: Chassis
var monster: Raker
var camera: Camera3D
var label: Label
var ready_to_drive := false
var running := false
var impact_seen := false
var since_impact := 0.0
var elapsed := 0.0
var close_view := false
var review_paused := false
var review_seen := false
var initial_health := 0.0

func _ready() -> void:
	get_window().title = "ApocalypseRV - Raker Impact"
	process_physics_priority = -10
	if not read_args:
		read_args = true
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--case="): selected = clampi(int(arg.trim_prefix("--case=")),0,3)
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var floor_shape := WorldBoundaryShape3D.new()
	collision.shape = floor_shape
	ground.add_child(collision)
	add_child(ground)
	RoadsideKit.part(self, Vector3(90,.2,320),Vector3(0,-.1,30),Color("585b53"))
	RoadsideKit.part(self,Vector3(12,.012,280),Vector3(0,.006,0),Color("363b40"))
	for z in range(-120,140,6):
		RoadsideKit.part(self,Vector3(.12,.02,3),Vector3(0,.018,z),Color("c6b990"))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48,-35,0)
	light.shadow_enabled = true
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("73828b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .65
	add_child(environment)
	var shell: Node3D = preload("res://rv/new_rv.tscn").instantiate()
	shell.position = Vector3(0,1.8,100 if selected == 1 else 15)
	add_child(shell)
	rv = shell.get_node("Chassis")
	rv.allow_test_controls = true
	monster = preload("res://enemies/raker.tscn").instantiate()
	monster.position = Vector3(1.4 if selected == 2 else 0.0,-.25,-22)
	monster.rotation.y = PI
	monster.loot_drops = {}
	monster.detection_range = 0.0
	monster.move_speed = 0.0
	add_child(monster)
	# Hold a real idle target in the lane. Its actual contact and ragdoll logic
	# continue normally; it is never teleported into the vehicle.
	monster.idle_timer = 1000.0
	monster.is_idle = true
	# Leave a clear lethal margin as cargo mass changes the actual wheel-driven speed.
	if selected == 1: monster.current_health = 40.0
	initial_health = monster.current_health
	camera = Camera3D.new()
	camera.fov = 55
	add_child(camera)
	camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(24,24)
	label.add_theme_font_size_override("font_size",22)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2)
	canvas.add_child(label)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for i in 90: await get_tree().physics_frame
	ready_to_drive = true
	print("PASS: RAKER_IMPACT_PLAYGROUND_READY case=",selected)
	if "--replay" in OS.get_cmdline_user_args(): start()

func start() -> void:
	if not ready_to_drive or impact_seen: return
	running = true
	rv.gear = 4
	rv.set_engine_running(true)
	rv.handbrake = false

func _physics_process(delta: float) -> void:
	if not ready_to_drive: return
	elapsed += delta
	if is_instance_valid(monster) and not impact_seen and monster.current_health < initial_health:
		impact_seen = true
		print("RAKER_IMPACT case=",selected," speed=",rv.road_speed()," hp=",monster.current_health," ragdoll=",monster.ragdoll.is_busy())
	if impact_seen:
		since_impact += delta
		# This is a stationary collision target, not a chase scenario. Once the
		# demonstrated recovery/landing is complete, keep it for inspection.
		if is_instance_valid(monster) and not monster.is_dead and not monster.ragdoll.is_busy() and monster.impact_stagger_remaining <= 0 and monster.is_on_floor():
			monster.velocity = Vector3.ZERO
			monster.set_physics_process(false)
		if "--review" in OS.get_cmdline_user_args() and not review_seen and since_impact > .3:
			review_seen = true
			_pause()
	if running and (not impact_seen or since_impact < .55):
		var error: float = SPEEDS[selected] - rv.road_speed()
		rv.control_override = {"throttle": clampf(error*.65,0,1), "brake": clampf(-error*.35,0,1)}
	else: rv.control_override = {"brake":1.0}

func _process(delta: float) -> void:
	if camera == null or rv == null: return
	var focus := Vector3(0,1,-22)
	if is_instance_valid(monster):
		focus = monster.global_position + Vector3.UP * 1.2
		if monster.ragdoll.active: focus = monster.ragdoll.bodies["pelvis"].global_position
	var offset := Vector3(6,3,-7) if close_view else Vector3(13,7,-11)
	camera.global_position = camera.global_position.lerp(focus+offset,1.0-exp(-delta*8))
	camera.look_at(focus)
	var state := "等待開始"
	if running: state = "行駛中"
	if impact_seen:
		state = "已起身" if is_instance_valid(monster) and not monster.ragdoll.is_busy() else "布娃娃"
		if is_instance_valid(monster) and monster.is_dead: state = "死亡布娃娃"
		if not is_instance_valid(monster): state = "屍體已回收"
	label.text = "RAKER 車撞 / 布娃娃\n%s\n%s · 車速 %.1f km/h · HP %.0f\nSpace 開始 · 1–4 切換案例 · R 重播\nF4 近景 / 全景 · F9 暫停 / 繼續" % [CASES[selected],state,rv.road_speed()*3.6,monster.current_health if is_instance_valid(monster) else 0.0]

func _pause() -> void:
	review_paused = not review_paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in get_children(): child.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = review_paused

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_SPACE: start()
		KEY_F4: close_view = not close_view
		KEY_F9: _pause()
		KEY_R: _reload()
		KEY_1,KEY_2,KEY_3,KEY_4:
			selected = event.keycode-KEY_1
			_reload()

func _reload() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _exit_tree() -> void:
	if review_paused: get_tree().paused = false
