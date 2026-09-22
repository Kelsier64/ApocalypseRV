extends Node3D
## Production wheel-driven RV and Raker, with repeatable speed presets.
var rv: Chassis
var player: CharacterBody3D
var monster: Raker
var observer: Camera3D
var status: Label
var camera_mode := 0
var cruise_index := -1
const CRUISE_SPEEDS := [0.0, 5.0, 10.0, 17.0, 25.0]
var ready_to_drive := false
var preview := false
var turn_replay := false
var turn_elapsed := 0.0
var grab_scenario := -1
var grab_delay := -1.0
var grab_seed := 218
var bite_review_frozen := false
var bite_review_seen := false
var clip_index := 0
const PREVIEW_CLIPS := ["idle", "walk", "chase", "sprint"]

func _ready() -> void:
	get_window().title = "ApocalypseRV - Raker Vehicle Playground"
	process_physics_priority = -10
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, .2, 2400)
	collision.shape = WorldBoundaryShape3D.new()
	collision.shape.plane = Plane(Vector3.UP, .1)
	ground.add_child(collision)
	ground.position.y = -.1
	add_child(ground)
	RoadsideKit.part(self, box.size, ground.position, Color("4d554d"))
	RoadsideKit.part(self, Vector3(18, .015, 2400), Vector3(0, .005, 0), Color("333b40"))
	for z in range(-1180, 1180, 10):
		RoadsideKit.part(self, Vector3(.15, .02, 4), Vector3(0, .02, z), Color("c9bd86"))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.shadow_enabled = true
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("697d8b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .65
	add_child(environment)
	var shell: Node3D = preload("res://rv/new_rv.tscn").instantiate()
	add_child(shell)
	rv = shell.get_node("Chassis")
	rv.position.y = 1.2
	rv.allow_test_controls = true
	rv.handbrake = true
	player = preload("res://player/player.tscn").instantiate()
	player.position = Vector3(4, -.25, 0)
	add_child(player)
	player.max_player_health = 10000
	player.current_player_health = 10000
	player._update_health_bar()
	observer = Camera3D.new()
	observer.fov = 58
	add_child(observer)
	observer.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(22, 110)
	status.add_theme_font_size_override("font_size", 19)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(status)
	# Let the production suspension settle before seating and spawning.
	for i in 60: await get_tree().physics_frame
	if "--grab-slow" in OS.get_cmdline_user_args(): Engine.time_scale = .1
	ready_to_drive = true
	seat_player()
	respawn_monster()
	if "--replay" in OS.get_cmdline_user_args(): cruise_index = 2
	if "--preview" in OS.get_cmdline_user_args(): preview_next_clip()
	if "--turns" in OS.get_cmdline_user_args():
		cruise_index = 2
		turn_replay = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--grab-seed="): grab_seed = int(arg.trim_prefix("--grab-seed="))
	for mode in ["--grab-ground", "--grab-cabin", "--grab-driver"]:
		if mode in OS.get_cmdline_user_args(): setup_grab(["--grab-ground", "--grab-cabin", "--grab-driver"].find(mode))
	print("PASS: RAKER_VEHICLE_PLAYGROUND_READY")

func seat_player() -> void:
	if not ready_to_drive: return
	if player.seated_in == null: rv.get_node("DriverSeat").interact_hold(player)
	rv.set_engine_running(true)
	rv.gear = 4
	rv.handbrake = false
	observer.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func respawn_monster() -> void:
	if is_instance_valid(monster): monster.free()
	monster = preload("res://enemies/raker.tscn").instantiate()
	monster.position = rv.to_global(Vector3(2, 0, 23))
	monster.position.y = -.25
	monster.detection_range = 150
	monster.lose_interest_range = 220
	add_child(monster)
	monster.target_player = player
	monster.ai_state = Monster.State.CHASE
	monster.loot_drops = {}
	preview = false

func foot_test() -> void:
	turn_replay = false
	cruise_index = -1
	rv.handbrake = true
	if player.seated_in != null: player.seated_in.exit_seat(true)
	player.global_position = Vector3(rv.global_position.x + 8, -.25, rv.global_position.z)
	respawn_monster()
	monster.global_position = player.global_position + Vector3(0, 0, 12)
	player.camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func preview_next_clip() -> void:
	turn_replay = false
	if not is_instance_valid(monster): respawn_monster()
	cruise_index = -1
	rv.handbrake = true
	preview = true
	monster.set_physics_process(false)
	monster.global_position = Vector3(rv.global_position.x + 10, -.25, rv.global_position.z)
	monster.rotation = Vector3.ZERO
	monster.velocity = Vector3.ZERO
	monster.get_node("BodyMesh").set_process(false)
	monster.get_node("BodyMesh").play(PREVIEW_CLIPS[clip_index], 1.0, true)
	clip_index = (clip_index + 1) % PREVIEW_CLIPS.size()
	camera_mode = 1
	observer.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not ready_to_drive: return
	match event.keycode:
		KEY_F1:
			turn_replay = false
			cruise_index = -1
			seat_player()
		KEY_F2:
			seat_player()
			cruise_index = (cruise_index + 1) % CRUISE_SPEEDS.size()
		KEY_F3:
			turn_replay = false
			cruise_index = -1
			rv.handbrake = true
		KEY_F4:
			camera_mode = (camera_mode + 1) % 3
			observer.current = true
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		KEY_F5: foot_test()
		KEY_F6: respawn_monster()
		KEY_F7:
			if is_instance_valid(monster): monster.take_damage(10)
		KEY_F8: preview_next_clip()
		KEY_F9:
			if bite_review_frozen:
				bite_review_frozen = false
				get_tree().paused = false
			elif preview and is_instance_valid(monster):
				var anim: AnimationPlayer = monster.get_node("BodyMesh").animation_player
				if anim.is_playing(): anim.pause()
				else: anim.play()
		KEY_F10:
			turn_replay = not turn_replay
			turn_elapsed = 0.0
			if turn_replay:
				seat_player()
				respawn_monster()
				cruise_index = 2
		KEY_F11: setup_grab((grab_scenario + 1) % 3)
		KEY_F12: setup_grab(maxi(0, grab_scenario))
		KEY_R: get_tree().reload_current_scene()
		_: return
	get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if not ready_to_drive or bite_review_frozen: return
	if grab_delay >= 0:
		grab_delay -= delta
		if grab_delay < 0:
			monster.ai_state = Monster.State.ATTACK
			monster.attack_timer = 0
	# Keep prolonged automatic runs inside the marked road and reset damaged
	# actors together; the infinite collision floor also prevents edge falls.
	if absf(rv.global_position.z) > 1100 or absf(rv.global_position.x) > 70 or rv.global_position.y < -5:
		ready_to_drive = false
		get_tree().reload_current_scene.call_deferred()
		return
	if cruise_index >= 0:
		var error: float = CRUISE_SPEEDS[cruise_index] - rv.road_speed()
		var steering := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		if turn_replay:
			turn_elapsed += delta
			if is_zero_approx(steering): steering = .3 * sin(maxf(0, turn_elapsed - 3.0) * .65)
		rv.control_override = {"throttle": clampf(error * .65, 0, 1), "brake": clampf(-error * .35, 0, 1), "steering": steering}
	elif player.seated_in != null and not preview:
		rv.control_override = {"throttle": Input.get_action_strength("move_forward"), "brake": Input.get_action_strength("move_back"), "steering": Input.get_action_strength("move_left") - Input.get_action_strength("move_right")}
	else: rv.control_override = {"brake": 1.0}

func _process(delta: float) -> void:
	if bite_review_frozen: return
	if not is_instance_valid(observer) or not is_instance_valid(rv): return
	if "--bite-review" in OS.get_cmdline_user_args() and not bite_review_seen and is_instance_valid(monster) and monster.grab.phase == monster.grab.Phase.BITE and monster.grab.elapsed >= .32:
		bite_review_seen = true
		bite_review_frozen = true
		process_mode = Node.PROCESS_MODE_ALWAYS
		for child in get_children(): child.process_mode = Node.PROCESS_MODE_PAUSABLE
		get_tree().paused = true
		print("BITE_REVIEW: contact pose paused; F9 resumes, F12 retries")
	var point := rv.global_position
	var offset := Vector3(17, 10, 25)
	if is_instance_valid(monster):
		match camera_mode:
			0: point = rv.global_position.lerp(monster.global_position, .55)
			1:
				point = monster.global_position + Vector3(0, 1, 0)
				offset = monster.global_basis * Vector3(4, 1.2, -2.5)
			2:
				point = monster.global_position + Vector3(0, 1, 0)
				offset = monster.global_basis * Vector3(5, .6, 0)
	observer.global_position = observer.global_position.lerp(point + offset, 1.0 - exp(-delta * 8.0))
	observer.look_at(point + Vector3(0, .5, 0))
	if not ready_to_drive:
		status.text = "追車測試場準備中…"
		return
	var mode := "手動駕駛" if player.seated_in != null else "步行追逐"
	if cruise_index >= 0: mode = "定速目標 %.0f km/h" % (CRUISE_SPEEDS[cruise_index] * 3.6)
	var detail := "怪物已死亡；F6 重生"
	if is_instance_valid(monster):
		detail = "怪物 %.1f km/h｜%s｜%s｜距車 %.1f m" % [Vector2(monster.velocity.x, monster.velocity.z).length() * 3.6, Raker.PursuitGait.keys()[monster.pursuit_gait], monster.get_node("BodyMesh").animation_player.current_animation, monster.global_position.distance_to(rv.global_position)]
	status.text = "RAKER 2.18 m｜%s｜車速 %.1f km/h｜狂奔上限 64.8 km/h\n%s\nW/S 油門/煞車 · A/D 轉向 · F1 手動駕駛 · F2 切換定速 0/18/36/61/90\nF3 停車 · F4 全景/近景/側面 · F5 下車測追逐 · F6 重生怪物\nF11 地面/車內/駕駛抓咬 · F12 重試\nF7 受傷中斷 · F8 步態預覽 · F9 暫停 · F10 轉彎回放 · R 重設%s" % [mode, rv.road_speed() * 3.6, detail, "\n動畫預覽中；F6 恢復實際 AI" if preview else ("\n轉彎回放中；F10 停止自動轉向" if turn_replay else "")]

func setup_grab(mode: int) -> void:
	if bite_review_frozen: get_tree().paused = false
	bite_review_frozen = false
	bite_review_seen = false
	if player.is_grabbed(): player.grab_control.end("playground_reset")
	grab_scenario = mode
	turn_replay = false
	cruise_index = -1
	rv.handbrake = true
	if is_instance_valid(player.seated_in): player.seated_in.exit_seat(true)
	player.is_player_dead = false
	player.max_player_health = 100
	player.current_player_health = 100
	player.grab_control.immunity = 0
	player._update_health_bar()
	respawn_monster()
	monster.grab.rng.seed = grab_seed
	monster.attack_timer = 2.0
	monster.reaction_remaining = 2.0
	grab_delay = 2.0
	if mode == 0:
		player.global_position = Vector3(rv.global_position.x + 9, .02, rv.global_position.z)
		monster.global_position = player.global_position + Vector3(0,-.25,-1.0)
		monster.rotation.y = PI
		player.rotation = Vector3.ZERO
		player.camera.rotation = Vector3.ZERO
		player.camera.current = true
	else:
		# Spawn inside the intact cabin, not through its door. The production
		# reach rays still decide whether the cockpit has sufficient clearance.
		player.global_position = rv.to_global(Vector3(0,.55,1.0))
		monster.global_position = rv.to_global(Vector3(0,.30,2.05))
		monster.global_rotation.y = rv.global_rotation.y
		monster.set_crouched(true)
		if mode == 2:
			rv.get_node("DriverSeat").interact_hold(player)
			monster.global_position = rv.to_global(rv.to_local(player.global_position) + Vector3(-.72,-.25,.72))
			monster.look_at(Vector3(player.global_position.x,monster.global_position.y,player.global_position.z))
			rv.set_engine_running(true)
			rv.gear = 1
			rv.handbrake = false
			cruise_index = 1
		else:
			player.rotation.y = rv.rotation.y + PI
			player.camera.rotation = Vector3.ZERO
			player.camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("GRAB_SCENARIO ",mode," seed=",grab_seed)

func _exit_tree() -> void:
	if bite_review_frozen: get_tree().paused = false
	Engine.time_scale = 1.0
