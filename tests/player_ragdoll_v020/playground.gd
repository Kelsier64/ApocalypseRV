extends Node3D
## Independent ragdoll acceptance stage; all geometry and control are test-owned.
const ACTOR = preload("res://tests/player_ragdoll_v020/actor.gd")
const OUTPUT := "res://docs/validation/player-v020-ragdoll/"
const CASES := ["stand_forward", "stand_back", "stand_left", "drop_face", "drop_back", "drop_right", "slope", "stairs", "animation_transition", "crouch_transition"]
var actor: CharacterBody3D
var camera: Camera3D
var label: Label
var selected_case := 0
var running := false
var replaying := false
var elapsed := 0.0
var terrain: Array[StaticBody3D] = []
var previous_physics_hz := 60
var previous_world: World3D
var test_world: World3D
const JOLT_TEST_SETTINGS := {
	"physics/jolt_physics_3d/simulation/velocity_steps": 32,
	"physics/jolt_physics_3d/simulation/position_steps": 32,
	"physics/jolt_physics_3d/simulation/penetration_slop": 0.003,
	"physics/jolt_physics_3d/simulation/continuous_cd_max_penetration": 0.10,
}

func _enter_tree() -> void:
	# This small, articulated test uses 120 Hz. Restore on exit; never save a
	# project setting or alter the production scene's simulation rate.
	previous_physics_hz = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 120
	# Jolt snapshots solver/contact settings when a physics space is created.
	# Construct a dedicated test World3D, then immediately restore global values.
	# Emit synchronously so native Jolt's cached settings see both transactions.
	var previous: Dictionary = {}
	for key: String in JOLT_TEST_SETTINGS:
		previous[key] = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, JOLT_TEST_SETTINGS[key])
	ProjectSettings.settings_changed.emit()
	previous_world = get_viewport().world_3d
	test_world = World3D.new()
	test_world.space # Force the isolated physics space to be created now.
	get_viewport().world_3d = test_world
	for key: String in previous:
		ProjectSettings.set_setting(key, previous[key])
	ProjectSettings.settings_changed.emit()

func _exit_tree() -> void:
	Engine.physics_ticks_per_second = previous_physics_hz
	get_viewport().world_3d = previous_world

func _ready() -> void:
	build_terrain()
	actor = ACTOR.new()
	actor.name = "TEST_AcceptanceActor"
	add_child(actor)
	if DisplayServer.get_name() != "headless":
		build_view()
	reset_case(0)
	if "--replay" in OS.get_cmdline_user_args():
		run_replay.call_deferred()

func build_terrain() -> void:
	add_ground("Floor", Vector3(0, -0.15, 0), Vector3(24, 0.30, 20), 0.0, Color("#747e83"))
	add_ground("Slope20deg", Vector3(4, 0.75, 0), Vector3(2.6, 0.25, 4), 20.0, Color("#647b68"))
	for i in 5:
		var height := 0.18 * (5 - i)
		add_ground("Step" + str(i), Vector3(-4, height * 0.5, -1.6 + i * 0.65), Vector3(2.6, height, 0.65), 0.0, Color("#8d8276"))

func add_ground(title: String, center: Vector3, size: Vector3, angle: float, color: Color) -> void:
	var ground := StaticBody3D.new()
	ground.name = title
	ground.position = center
	ground.rotation_degrees.x = angle
	ground.collision_layer = 1
	ground.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	ground.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	mesh.material_override = material
	ground.add_child(mesh)
	add_child(ground)
	terrain.append(ground)

func build_view() -> void:
	get_window().size = Vector2i(1120, 840)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#414c56")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#e7edf2")
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 24
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.near = 0.025
	camera.far = 50
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.8
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 19)
	canvas.add_child(label)
	print("RAGDOLL_VISUAL_ENV ", JSON.stringify({"godot": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "gpu": RenderingServer.get_video_adapter_name(), "physics": ProjectSettings.get_setting("physics/3d/physics_engine")}))

func reset_case(index: int) -> void:
	selected_case = index
	running = false
	elapsed = 0.0
	actor.recover_at(Vector3(0, 0.025, 0))
	actor.set_physics_process(false)
	var pose := 0.0
	var rotation := Basis.IDENTITY
	var pivot := Vector3(0, 1.60, 0)
	if index == 3:
		rotation = Basis(Vector3.RIGHT, deg_to_rad(85))
	elif index == 4:
		rotation = Basis(Vector3.RIGHT, deg_to_rad(-85))
	elif index == 5:
		rotation = Basis(Vector3.FORWARD, deg_to_rad(85))
	elif index == 6:
		actor.position = Vector3(4, 1.40, -1.20)
	elif index == 7:
		rotation = Basis(Vector3.RIGHT, deg_to_rad(85))
		pivot = Vector3(-4, 1.65, -0.5)
	elif index == 8:
		pose = 2.5
	elif index == 9:
		pose = 4.0
	if index in [3, 4, 5, 7]:
		actor.transform = Transform3D(rotation, pivot - rotation * Vector3(0, 0.855, -0.052))
	actor.set_test_pose(pose)
	if camera:
		frame_camera()
	update_label()

func start_case() -> void:
	if running:
		return
	running = true
	elapsed = 0.0
	var impulse := Vector3(0, 0, 12)
	if selected_case == 1:
		impulse = Vector3(0, 0, -12)
	elif selected_case == 2:
		impulse = Vector3(12, 0, 0)
	elif selected_case in [3, 4, 5]:
		impulse = Vector3.ZERO
	elif selected_case in [6, 7]:
		impulse = Vector3(0, 0, 12)
	actor.start_ragdoll(impulse)
	actor.set_physics_process(true)
	update_label()

func recover_control() -> bool:
	var pelvis: PhysicalBone3D = actor.bodies["pelvis"]
	var origin := pelvis.global_position
	var space := get_world_3d().direct_space_state
	# Find support and verify capsule clearance on the actual terrain.
	for offset in [Vector3.ZERO, Vector3(0.6, 0, 0), Vector3(-0.6, 0, 0), Vector3(0, 0, 0.8), Vector3(0, 0, -0.8), Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0)]:
		var ray := PhysicsRayQueryParameters3D.create(origin + offset + Vector3.UP * 3, origin + offset + Vector3.DOWN * 5, 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var feet: Vector3 = hit.position + Vector3.UP * 0.06
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = actor.controller_shape.shape
		query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.8)
		query.collision_mask = 1
		if not space.intersect_shape(query, 1).is_empty():
			continue
		actor.recover_at(feet)
		actor.set_physics_process(true)
		running = false
		update_label()
		return true
	return false

func _physics_process(delta: float) -> void:
	if running:
		elapsed += delta
	if camera:
		frame_camera()
		update_label()
	if not replaying and not actor.ragdoll:
		actor.move_request = Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), 0, float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).normalized()

func frame_camera() -> void:
	var target: Vector3 = actor.bodies["pelvis"].global_position if actor.ragdoll else actor.global_position + Vector3.UP * 0.75
	# View the lateral fall from the opposite side so the ramp cannot occlude it.
	camera.position = target + (Vector3(-3.2, 2.5, -4.0) if selected_case == 2 else Vector3(3.2, 2.5, 4.0))
	camera.look_at(target)

func update_label() -> void:
	if label:
		label.text = "PLAYER v020 | " + CASES[selected_case] + (" | PHYSICS %.1fs" % elapsed if running else " | CONTROL / READY") + "\nF1-F10 scenarios | Space fall | R recover | C colliders | T TEST clip | WASD move | Esc close\n14 bodies / 67.0 kg / 120 Hz / 41 unchanged deform bones / independent test only"

func _unhandled_key_input(event: InputEvent) -> void:
	if replaying or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	if key == null:
		return
	if key.keycode >= KEY_F1 and key.keycode <= KEY_F10:
		reset_case(key.keycode - KEY_F1)
	elif key.keycode == KEY_SPACE:
		start_case()
	elif key.keycode == KEY_R:
		recover_control()
	elif key.keycode == KEY_C:
		actor.set_debug(not actor.debug_shapes)
	elif key.keycode == KEY_T and not actor.ragdoll:
		actor.animate = not actor.animate
		actor.set_physics_process(true)
	elif key.keycode == KEY_ESCAPE:
		get_tree().quit()

func capture(filename: String) -> void:
	if not camera:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + filename + ".png")

func run_replay() -> void:
	replaying = true
	var visual_cases: Array = []
	reset_case(0)
	actor.set_debug(true)
	await get_tree().create_timer(0.25).timeout
	await capture("collision_configuration")
	actor.set_debug(false)
	for i in CASES.size():
		reset_case(i)
		await get_tree().create_timer(0.25).timeout
		if i == 2:
			actor.move_request = Vector3.RIGHT
			actor.set_physics_process(true)
			await get_tree().create_timer(0.3).timeout
		if i == 8:
			actor.animate = true
			actor.set_physics_process(true)
			await get_tree().create_timer(0.1).timeout
		await capture(CASES[i] + "_start")
		start_case()
		await get_tree().create_timer(1.3).timeout
		await capture(CASES[i] + "_impact")
		await get_tree().create_timer(10.7).timeout
		await capture(CASES[i] + "_settled")
		var max_speed := 0.0
		for body: PhysicalBone3D in actor.bodies.values():
			max_speed = maxf(max_speed, body.linear_velocity.length())
		var recovered := recover_control()
		await get_tree().create_timer(0.5).timeout
		var control_start := actor.global_position
		actor.move_request = Vector3.LEFT if i == 2 else Vector3.RIGHT
		await get_tree().create_timer(0.8).timeout
		actor.move_request = Vector3.ZERO
		await capture(CASES[i] + "_recovered")
		visual_cases.append({"case": CASES[i], "recovered": recovered, "settled_speed_m_s": max_speed, "control_distance_m": actor.global_position.distance_to(control_start)})
		print("REPLAY_CASE ", CASES[i], " recovered=", recovered)
	FileAccess.open(OUTPUT + "visual_run.json", FileAccess.WRITE).store_string(JSON.stringify({"godot": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "gpu": RenderingServer.get_video_adapter_name(), "physics": ProjectSettings.get_setting("physics/3d/physics_engine"), "physics_hz": Engine.physics_ticks_per_second, "test_world_settings": JOLT_TEST_SETTINGS, "cases": visual_cases}, "\t"))
	replaying = false
	print("PASS: ragdoll visual replay complete")
	if "--quit-replay" in OS.get_cmdline_user_args():
		get_tree().quit()
