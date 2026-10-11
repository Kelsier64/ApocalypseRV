extends Node3D
## Small native acceptance range. Actors and weapon inputs use production code.
var player: CharacterBody3D
var raker: Monster
var barrel: BarrelMan
var blocked: Monster
var giant: Monster
var loose_pistol: Item
var observer: Camera3D
var status: Label
var observer_view := false
var replay_running := false
var replay_finished := false
var capture_index := 0

func _ready() -> void:
	set_meta("entity_domain", true)
	get_window().title = "ApocalypseRV - Pistol Validation Range"
	# Native virtual keys are mapped only in this fixture.
	for binding in [["move_forward", KEY_W], ["move_back", KEY_S], ["move_left", KEY_A], ["move_right", KEY_D], ["sprint", KEY_SHIFT], ["jump", KEY_SPACE], ["weapon_reload", KEY_R], ["interact", KEY_E], ["place_equipment", KEY_F], ["drop_item", KEY_G], ["hotbar_1", KEY_1], ["hotbar_2", KEY_2]]:
		var key := InputEventKey.new()
		key.keycode = binding[1]
		InputMap.action_add_event(binding[0], key)
	box(Vector3(0, -0.15, -12), Vector3(42, 0.3, 50), Color(0.2, 0.24, 0.23))
	box(Vector3(4, 1.2, -8), Vector3(3, 2.4, 0.25), Color(0.6, 0.34, 0.14))
	for x in [-6.0, 0.0, 6.0]:
		box(Vector3(x, 0.015, -5), Vector3(0.04, 0.03, 10), Color(0.9, 0.76, 0.3), false)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.28, 0.36, 0.42)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.87, 1.0)
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -35, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)
	raker = target("res://enemies/raker.tscn", Vector3(-4, 0, -12))
	barrel = target("res://enemies/barrel_man.tscn", Vector3(0, 0, -12)) as BarrelMan
	blocked = target("res://enemies/raker.tscn", Vector3(4, 0, -12))
	giant = target("res://enemies/slender_speaker/slender_speaker.tscn", Vector3(12, 0, -23))
	sign_at("RAKER\n140 HP / 6 hits", Vector3(-4, 3.3, -12))
	sign_at("BARREL MAN\n60 HP / detonates", Vector3(0, 2.8, -12))
	sign_at("SOLID WALL\nblocks bullets", Vector3(4, 3.0, -8))
	sign_at("SLENDER SPEAKER\ninvincible", Vector3(12, 16.1, -23))
	box(Vector3(-3, 0.45, -1), Vector3(1.6, 0.9, 1), Color(0.35, 0.43, 0.47))
	for sample in [["res://props/pistol.tscn", Vector3(-3.25, 1.0, -1)], ["res://props/pistol_ammo.tscn", Vector3(-2.8, 1.0, -1)]]:
		var item: Item = load(sample[0]).instantiate()
		item.position = sample[1]
		WorldEntities.get_container(self).add_child(item)
		if sample[0] == "res://props/pistol.tscn": loose_pistol = item
	sign_at("LOOSE PICKUPS\nE pickup / F place / G drop", Vector3(-3, 1.8, -1), 0.0015)
	player = load("res://player/player.tscn").instantiate()
	player.position = Vector3(-4, 0.05, 1)
	add_child(player)
	player.add_item("Pistol", false, "res://props/pistol.tscn", {"pistol": {"loaded_rounds": 6}})
	player.add_item("Pistol ammunition", false, "res://props/pistol_ammo.tscn")
	player.camera.look_at(raker.global_position + Vector3.UP * 1.5)
	observer = Camera3D.new()
	observer.position = Vector3(8, 5, 6)
	add_child(observer)
	observer.look_at(Vector3(0, 1.2, -6))
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(22, 145)
	status.add_theme_font_size_override("font_size", 20)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 5)
	layer.add_child(status)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().physics_frame
	if DisplayServer.get_name() != "headless": get_window().size = Vector2i(1280, 720)
	print("PISTOL_PLAYGROUND_READY magazine=6 reserve=24; F2 wall lane, F3 reset, F4 observer, F6 replay, F7 giant, F8 loose pistol")
	if OS.get_cmdline_user_args().has("--replay"): replay.call_deferred()
	elif OS.get_cmdline_user_args().has("--pickup"): focus_pickup()

func box(at: Vector3, size: Vector3, color: Color, solid := true) -> Node3D:
	var object: Node3D = StaticBody3D.new() if solid else Node3D.new()
	object.position = at
	var mesh := MeshInstance3D.new()
	var shape_mesh := BoxMesh.new()
	shape_mesh.size = size
	mesh.mesh = shape_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	object.add_child(mesh)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		object.add_child(collision)
	add_child(object)
	return object

func target(path: String, at: Vector3) -> Monster:
	var monster: Monster = load(path).instantiate()
	monster.position = at
	add_child(monster)
	monster.set_physics_process(false)
	return monster

func sign_at(text: String, at: Vector3, pixel_size := 0.0025) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 46
	label.pixel_size = pixel_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	add_child(label)

func _process(_delta: float) -> void:
	if player == null: return
	status.text = "PISTOL RANGE | WASD move / Space jump / Shift sprint\nLeft click fire / hold right aim / R reload / 1 pistol / 2 ammo / E pickup / F place / G drop\nF2 wall / F3 reset / F4 observer / F6 replay / F7 giant / F8 pickup / Esc settings\nMagazine: %d / 12 | reserve: %d | reload: %.2f s | aiming: %.0f%%" % [player.weapon.loaded_rounds(), player.weapon.reserve_rounds(), player.weapon.reload_remaining, player.weapon.aim_weight * 100.0]
	status.text += "\nRaker: %.0f HP | barrel: %.0f HP | wall target: %.0f HP | giant: %.0f HP" % [raker.current_health if is_instance_valid(raker) else 0.0, barrel.current_health if is_instance_valid(barrel) else 0.0, blocked.current_health, giant.current_health]
	if replay_finished: status.text += "\nREPLAY COMPLETE — F3 resets; manual controls remain available"

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or player.in_ui_mode or player.settings_open: return
	match event.keycode:
		KEY_F2: focus(Vector3(4, 0.05, -6.9), blocked.global_position + Vector3.UP * 1.5)
		KEY_F3: get_tree().reload_current_scene()
		KEY_F4:
			observer_view = not observer_view
			if observer_view:
				observer.global_position = player.camera.global_position + player.camera.global_basis * Vector3(1.2, -0.08, -1.6)
				observer.look_at(player.global_position + Vector3.UP * 1.45 - player.camera.global_basis.z * 0.35)
				observer.current = true
				capture("observer")
			else: player.camera.current = true
		KEY_F6:
			if not replay_running: replay.call_deferred()
		KEY_F7: focus(Vector3(7, 0.05, -10), giant.global_position + Vector3.UP * 7.5)
		KEY_F8: focus_pickup()

func focus_pickup() -> void:
	await get_tree().create_timer(.5).timeout
	if not is_instance_valid(loose_pistol) or loose_pistol.is_queued_for_deletion(): return
	var point := loose_pistol.to_global(Vector3(0, .052, -.036))
	focus(Vector3(point.x, player.global_position.y, point.z + 1.0), point)

func focus(at: Vector3, point: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	var horizontal := Vector3(point.x, at.y, point.z)
	if horizontal.distance_squared_to(at) > 0.0001: player.look_at(horizontal)
	player.camera.look_at(point)
	player.camera.current = true
	observer_view = false

func input_click(button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)

func input_reload() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_R
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().physics_frame
	event = InputEventKey.new()
	event.keycode = KEY_R
	event.pressed = false
	Input.parse_input_event(event)

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/pistol-playground-captures")
	get_viewport().get_texture().get_image().save_png("res://.godot/pistol-playground-captures/%02d-%s.png" % [capture_index, label])
	capture_index += 1

func replay() -> void:
	if replay_running: return
	replay_running = true
	replay_finished = false
	print("PISTOL_REPLAY_START")
	await get_tree().create_timer(0.8).timeout
	await capture("ready")
	input_click(MOUSE_BUTTON_RIGHT, true)
	await get_tree().create_timer(0.2).timeout
	await capture("aimed")
	# First shot is held for > cooldown: production input must remain semi-auto.
	input_click(MOUSE_BUTTON_LEFT, true)
	await capture("first-shot")
	await get_tree().create_timer(0.7).timeout
	print("PISTOL_REPLAY_HELD magazine=", player.weapon.loaded_rounds(), " raker_hp=", raker.current_health)
	input_click(MOUSE_BUTTON_LEFT, false)
	for index in 5:
		input_click(MOUSE_BUTTON_LEFT, true)
		await get_tree().create_timer(0.04).timeout
		input_click(MOUSE_BUTTON_LEFT, false)
		await get_tree().create_timer(0.31).timeout
	input_click(MOUSE_BUTTON_RIGHT, false)
	print("PISTOL_REPLAY_RAKER dead=", raker.is_dead, " magazine=", player.weapon.loaded_rounds())
	await capture("empty-raker")
	await input_reload()
	await get_tree().create_timer(0.6).timeout
	await capture("reloading")
	await get_tree().create_timer(1.0).timeout
	print("PISTOL_REPLAY_RELOAD magazine=", player.weapon.loaded_rounds(), " reserve=", player.weapon.reserve_rounds())
	focus(Vector3(0, 0.05, 1), barrel.global_position + Vector3.UP * 0.5)
	for index in 3:
		input_click(MOUSE_BUTTON_LEFT, true)
		await get_tree().create_timer(0.04).timeout
		input_click(MOUSE_BUTTON_LEFT, false)
		await get_tree().create_timer(0.31).timeout
	print("PISTOL_REPLAY_BARREL dead=", barrel.is_dead if is_instance_valid(barrel) else true)
	await capture("barrel")
	focus(Vector3(4, 0.05, -6.9), blocked.global_position + Vector3.UP * 1.5)
	input_click(MOUSE_BUTTON_LEFT, true)
	await get_tree().create_timer(0.04).timeout
	input_click(MOUSE_BUTTON_LEFT, false)
	await get_tree().create_timer(0.35).timeout
	print("PISTOL_REPLAY_WALL target_hp=", blocked.current_health)
	await capture("wall")
	focus(Vector3(7, 0.05, -10), giant.global_position + Vector3.UP * 7.5)
	input_click(MOUSE_BUTTON_LEFT, true)
	await get_tree().create_timer(0.04).timeout
	input_click(MOUSE_BUTTON_LEFT, false)
	await get_tree().create_timer(0.35).timeout
	print("PISTOL_REPLAY_GIANT hp=", giant.current_health)
	await capture("giant")
	replay_running = false
	replay_finished = true
	var valid: bool = (not is_instance_valid(raker) or raker.is_dead) and (not is_instance_valid(barrel) or barrel.is_dead) and blocked.current_health == blocked.max_health and giant.current_health == giant.max_health and player.weapon.loaded_rounds() == 7 and player.weapon.reserve_rounds() == 12
	print("PISTOL_REPLAY_COMPLETE valid=", valid, " magazine=", player.weapon.loaded_rounds(), " reserve=", player.weapon.reserve_rounds())
	if OS.get_cmdline_user_args().has("--headless-check"):
		if valid: print("PASS: pistol native range replay behavior")
		else: push_error("Pistol replay expectations failed")
		# Flush gameplay actors and their transient ragdoll/FX resources first.
		var tree := get_tree()
		var exit_code := 0 if valid else 1
		for sound in find_children("*", "AudioStreamPlayer3D", true, false):
			sound.stop()
			sound.stream = null
		# Let the audio thread release stopped stream playback before teardown.
		await tree.create_timer(0.2).timeout
		tree.create_timer(0.2).timeout.connect(func() -> void: tree.quit(exit_code))
		queue_free()
