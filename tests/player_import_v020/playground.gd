extends Node3D
## Visual acceptance only; no production player controller or ragdoll nodes.
const MODEL = preload("res://assets/models/player_test_v020/player_export_test_v020.glb")
const LOCAL_VIEW = preload("res://tests/player_import_v020/local_view.gd")
const CLIP := &"TEST_v020_POSE_SAMPLES"
const OUTPUT := "res://docs/validation/player-v020/"
const POSES := ["neutral", "side", "forward", "elbow", "crouch", "head", "fingers", "fp_pose"]
var model: Node3D
var animation: AnimationPlayer
var camera: Camera3D
var label: Label
var playing := false
var time := 0.0
var capturing := false
var view := 0

func _ready() -> void:
	DisplayServer.window_set_title("Player v020 - Import Acceptance")
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
	sun.position = Vector3(-3, 5, 4)
	sun.look_at(Vector3(0, 0.8, 0))
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.light_cull_mask = 7
	sun.directional_shadow_max_distance = 12.0
	var fill := DirectionalLight3D.new()
	add_child(fill)
	fill.rotation_degrees = Vector3(-35, 155, 0)
	fill.light_energy = 0.4
	fill.light_cull_mask = 7
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#737c80")
	ground_material.roughness = 1.0
	floor_mesh.material_override = ground_material
	add_child(floor_mesh)
	model = MODEL.instantiate()
	add_child(model)
	print("LOCAL_VIEW ", JSON.stringify(LOCAL_VIEW.configure(model)))
	animation = model.get_node("AnimationPlayer")
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play(CLIP)
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.near = 0.025
	camera.far = 30
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(24, 16)
	label.add_theme_font_size_override("font_size", 19)
	canvas.add_child(label)
	select_pose(0)
	print("VISUAL_ENV ", JSON.stringify({"godot": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "gpu": RenderingServer.get_video_adapter_name(), "physics": ProjectSettings.get_setting("physics/3d/physics_engine")}))
	if "--capture" in OS.get_cmdline_user_args():
		capture_all.call_deferred()

func _process(delta: float) -> void:
	if playing and not capturing:
		time = fmod(time + delta, 8.0)
		animation.seek(time, true)

func _unhandled_key_input(event: InputEvent) -> void:
	if capturing or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	if key == null:
		return
	if key.keycode >= KEY_F1 and key.keycode <= KEY_F8:
		select_pose(key.keycode - KEY_F1)
	elif key.keycode == KEY_F9:
		first_person(false)
	elif key.keycode == KEY_F10:
		first_person(true)
	elif key.keycode == KEY_F11:
		select_pose(0)
		camera.size = 3.5
		camera.position = Vector3(0, 3, -4)
		camera.look_at(Vector3(0.5, 0.5, -0.5))
		describe("OBSERVER: complete head + complete shadow")
	elif key.keycode == KEY_SPACE:
		playing = not playing
		describe("TEST playback" if playing else "Paused")
	elif key.keycode == KEY_P:
		capture_all()
	elif key.keycode == KEY_ESCAPE:
		get_tree().quit()

func describe(title: String) -> void:
	label.text = "PLAYER v020 | " + title + "\nF1-F8 poses | F9 look down | F10 hands | F11 observer | Space TEST playback | P capture | Esc close\n11 meshes / 41 deform bones / 1.60 m / source materials / no ragdoll"

func select_pose(index: int) -> void:
	playing = false
	view = index
	time = index
	animation.seek(time, true)
	camera.cull_mask = 3
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.95
	camera.position = Vector3(2.8, 2.3, 5)
	camera.look_at(Vector3(0, 0.82, 0))
	describe(POSES[index])

func first_person(hands: bool) -> void:
	select_pose(7 if hands else 0)
	view = 9 if hands else 8
	camera.cull_mask = 5
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 90
	# Inspection cameras only. Forward clearance keeps the lens out of the collar.
	camera.position = Vector3(0, 1.53, 0.12 if hands else 0.20)
	camera.rotation_degrees = Vector3(-25 if hands else -82, 180, 0)
	describe("LOCAL: hands / head camera-culled" if hands else "LOCAL: look down / head camera-culled")

func screenshot(filename: String) -> void:
	label.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(OUTPUT + filename + ".png")
	label.visible = true
	if result != OK:
		push_error("Screenshot save failed: " + filename)

func capture_all() -> void:
	if capturing:
		return
	capturing = true
	for i in POSES.size():
		select_pose(i)
		await screenshot("godot_" + POSES[i])
	first_person(false)
	await screenshot("godot_first_person_down")
	first_person(true)
	await screenshot("godot_first_person_hands")
	select_pose(0)
	camera.size = 3.5
	camera.position = Vector3(0, 3, -4)
	camera.look_at(Vector3(0.5, 0.5, -0.5))
	describe("OBSERVER: complete head + complete shadow")
	await screenshot("godot_observer_shadow")
	camera.cull_mask = 5
	describe("LOCAL BODY LAYER: hidden head / full shadow retained")
	await screenshot("godot_local_layer_shadow")
	select_pose(0)
	capturing = false
	print("PASS: visual captures saved; manual window verification remains separate")
