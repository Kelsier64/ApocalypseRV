extends Node3D
## Production actor/input; observer and capture logic exist only in this scene.
const PLAYER = preload("res://player/player.tscn")
const OUT := "res://docs/validation/player-animations-v021/"
var capture_directory := OUT
var actor: CharacterBody3D
var observer: Camera3D
var label: Label
var replaying := false
var jump_review := false

func _ready() -> void:
	get_window().title = "ApocalypseRV - Player Animation Acceptance"
	get_window().size = Vector2i(1200, 850)
	if "--hands" in OS.get_cmdline_user_args(): capture_directory += "hands/"
	if "--wrists-only" in OS.get_cmdline_user_args(): capture_directory = OUT + "wrist-only/"
	if "--relaxed-fingers" in OS.get_cmdline_user_args(): capture_directory = OUT + "relaxed-fingers/"
	jump_review = "--jump" in OS.get_cmdline_user_args()
	if jump_review: capture_directory = OUT + "jump/"
	DirAccess.make_dir_recursive_absolute(capture_directory)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	collider.shape.size = Vector3(200, .2, 200)
	collider.position.y = -.1
	floor_body.add_child(collider)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = collider.shape.size
	floor_mesh.position = collider.position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.19, .22, .25)
	floor_mesh.material_override = material
	floor_body.add_child(floor_mesh)
	add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.12, .14, .17)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .65
	add_child(environment)
	actor = PLAYER.instantiate()
	add_child(actor)
	observer = Camera3D.new()
	if jump_review: observer.fov = 50
	add_child(observer)
	observer.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(20, 140)
	label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(label)
	if "--replay" in OS.get_cmdline_user_args(): replay.call_deferred()

func _process(_delta: float) -> void:
	if observer == null: return
	var center := actor.position + Vector3(0, .95, 0)
	if jump_review: center.y = 1.25
	if actor.is_player_dead and actor.ragdoll_control.active:
		center = actor.ragdoll_control.bodies["pelvis"].global_position
	observer.position = center + Vector3(2.3, .55, -2.9)
	observer.look_at(center)
	label.text = "PLAYER v021 | 60 Hz | " + actor.get_node("Visuals/Locomotion").current_clip + "\nWASD / Shift / Space | F1 first person | F2 observer | F3 replay | Esc close"

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F1:
			actor.camera.rotation.x = deg_to_rad(-75)
			actor.camera.make_current()
		KEY_F2: observer.make_current()
		KEY_F3:
			if not replaying: replay()
		KEY_ESCAPE: get_tree().quit()

func wait_seconds(seconds: float) -> void:
	for frame in ceili(seconds * Engine.physics_ticks_per_second): await get_tree().physics_frame

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_directory + name + ".png")

func replay() -> void:
	if replaying: return
	if jump_review:
		await replay_jumps()
		return
	replaying = true
	await wait_seconds(.8)
	await capture("idle")
	for gait in ["jog", "run"]:
		for direction in ["forward", "back", "left", "right"]:
			actor.current_stamina = actor.MAX_STAMINA
			actor.stamina_exhausted = false
			Input.action_press("move_" + direction)
			if gait == "run": Input.action_press("sprint")
			await wait_seconds(.7)
			await capture(gait + "_" + direction)
			if direction == "forward":
				actor.camera.rotation.x = deg_to_rad(-75)
				actor.camera.make_current()
				await capture(gait + "_first_person")
				observer.make_current()
			await wait_seconds(.8)
			Input.action_release("move_" + direction)
			Input.action_release("sprint")
			await wait_seconds(.3)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_seconds(.4)
	actor.take_damage(1000)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await wait_seconds(.5)
	await capture("run_death")
	observer.make_current()
	await capture("run_death_external")
	await wait_seconds(2.0)
	await capture("recovered_idle")
	print("PASS: rendered production locomotion replay completed at ", Engine.physics_ticks_per_second, " Hz")
	replaying = false
	if "--replay" in OS.get_cmdline_user_args(): get_tree().quit()

func replay_jumps() -> void:
	replaying = true
	await wait_seconds(.5)
	for movement in ["standing", "jog", "run"]:
		actor.current_stamina = actor.MAX_STAMINA
		actor.stamina_exhausted = false
		if movement != "standing": Input.action_press("move_forward")
		if movement == "run": Input.action_press("sprint")
		await wait_seconds(.3)
		Input.action_press("jump")
		await get_tree().physics_frame
		Input.action_release("jump")
		var captured: Array[String] = []
		for frame in 120:
			await get_tree().physics_frame
			var clip: String = actor.get_node("Visuals/Locomotion").current_clip
			if clip.begins_with("jump_") and clip not in captured:
				captured.append(clip)
				await wait_seconds(.08)
				await capture(movement + "_" + clip)
				if clip != "jump_land":
					actor.camera.rotation.x = deg_to_rad(-75)
					actor.camera.make_current()
					await capture(movement + "_" + clip + "_first_person")
					observer.make_current()
			if captured.size() == 3 and not clip.begins_with("jump_"): break
		print("JUMP_REPLAY ", movement, " ", captured)
		Input.action_release("move_forward")
		Input.action_release("sprint")
		await wait_seconds(.4)
		await capture(movement + "_recovered")
		if captured.size() != 3:
			push_error("Jump replay missed a phase: " + movement)
			replaying = false
			return
	print("PASS: rendered standing, jogging and sprinting jumps completed at ", Engine.physics_ticks_per_second, " Hz")
	replaying = false
	if "--replay" in OS.get_cmdline_user_args(): get_tree().quit()
