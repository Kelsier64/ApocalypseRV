extends Node3D
## Manual and repeatable visual harness using production RV/actor scenes.
var rv: Chassis
var player: CharacterBody3D
var monster: Monster
var observer: Camera3D
var status: Label
var replay := false
var driving := false
var elapsed := 0.0
var player_climbed := false
var monster_climbed := false
var driver_demo := false
var debug_next_sample: float = 0.0

func _ready() -> void:
	process_physics_priority = -10
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 0.2, 200)
	ground_shape.shape = box
	ground.position.y = -0.1
	ground.add_child(ground_shape)
	var mesh := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = box.size
	mesh.mesh = ground_mesh
	ground.add_child(mesh)
	add_child(ground)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.25, 0.35, 0.5)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var vehicle: Node3D = preload("res://rv/new_rv.tscn").instantiate()
	add_child(vehicle)
	rv = vehicle.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	rv.position.y = 1.2
	player = preload("res://player/player.tscn").instantiate()
	player.position = Vector3(2.65, 0.05, 0)
	player.rotation.y = PI / 2.0
	add_child(player)
	var marker := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.5
	capsule.radius = 0.4
	marker.mesh = capsule
	marker.position.y = 1.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.55, 1.0)
	marker.material_override = material
	player.add_child(marker)
	var monster_scene: PackedScene = load("res://enemies/raker.tscn" if "--raker" in OS.get_cmdline_user_args() else "res://enemies/zombie.tscn")
	monster = monster_scene.instantiate()
	monster.position = Vector3(-2.65, 0.05, 0)
	monster.rotation.y = -PI / 2.0
	add_child(monster)
	if "--climb-debug" in OS.get_cmdline_user_args(): monster.debug_climb_messages = true
	observer = Camera3D.new()
	add_child(observer)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(20, 80)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(status)
	if "--replay" in OS.get_cmdline_user_args():
		_start_replay()

func _start_replay() -> void:
	replay = true
	elapsed = 0.0
	# Keep the target alive long enough to inspect support and then press F5.
	player.max_player_health = 10000.0
	player.current_player_health = 10000.0
	player._update_health_bar()
	player_climbed = false
	monster_climbed = false
	observer.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Input.action_press("move_forward")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F2:
			replay = false
			Input.action_release("move_forward")
			driving = not driving
		KEY_F3:
			_start_replay()
		KEY_F4:
			observer.current = not observer.current
			if not observer.current:
				player.camera.current = true
		KEY_F5:
			driver_demo = true
			Input.action_release("move_forward")
			player.enter_seat_mode(rv.get_node("DriverSeat"))
			observer.current = true
		KEY_R:
			Input.action_release("move_forward")
			get_tree().reload_current_scene()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if not is_instance_valid(monster):
		status.text = "RV CLIMB PLAYGROUND | Monster defeated after release. R: reset"
		return
	if replay and not driver_demo and elapsed > 6.0 and "--seat-after-climb" in OS.get_cmdline_user_args():
		driver_demo = true
		player.enter_seat_mode(rv.get_node("DriverSeat"))
	if "--climb-debug" in OS.get_cmdline_user_args() and elapsed >= debug_next_sample:
		debug_next_sample = elapsed + 1.0
		print("REPLAY ", elapsed, " player=", rv.to_local(player.global_position), " monster=", rv.to_local(monster.global_position), " mode=", monster.boarding.mode, " locomotion=", monster.locomotion_state, " grip=", monster.boarding.grip, " strain=", monster.boarding.strain, " support=", monster.rv_support.surface)
	if replay:
		if player.locomotion_state == player.LocomotionState.CLIMBING:
			player_climbed = true
		if monster.locomotion_state == monster.LocomotionState.CLIMBING:
			monster_climbed = true
		if driver_demo or (player_climbed and player.locomotion_state == player.LocomotionState.NORMAL):
			Input.action_release("move_forward")
		# This replay validates carried support, not interception probability.
		# Start movement only after both actors have actually caught a surface.
		driving = elapsed > 0.7 and player_climbed and monster_climbed
	if driving:
		rv.position += -rv.basis.z * 4.0 * delta
		rv.rotate_y(0.12 * delta)
	observer.position = rv.to_global(Vector3(11, 7, 12))
	observer.look_at(rv.to_global(Vector3(0, 1.5, 0)))
	status.text = "RV CLIMB PLAYGROUND | Blue: player / Pale: monster\nF2: move/stop | F3: auto climb | F4: camera | F5: seat player / roof attack | R: reset\nPlayer: %s  y=%.2f | Monster: %s  y=%.2f\nRV motion: %s | roof HP: %s" % [
		player.LocomotionState.keys()[player.locomotion_state], rv.to_local(player.global_position).y,
		monster.LocomotionState.keys()[monster.locomotion_state], rv.to_local(monster.global_position).y,
		str(driving), str(rv.get_node("Ceiling").current_health) if rv.has_node("Ceiling") else "DESTROYED"]

func _exit_tree() -> void:
	Input.action_release("move_forward")
