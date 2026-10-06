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
var cabin_view := false
var side_route := false
var top_review_time := 0.0

func _ready() -> void:
	get_window().title = "ApocalypseRV - Ladder Acceptance"
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
	marker.visible = "--animation-review" not in OS.get_cmdline_user_args()
	var monster_scene: PackedScene = load("res://enemies/raker.tscn")
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
	elif "--art-review" in OS.get_cmdline_user_args():
		monster.set_physics_process(false)
		cabin_view = true
		observer.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _start_replay() -> void:
	Input.action_release("move_back")
	top_review_time = 0.0
	if is_instance_valid(player.seated_in): player.seated_in.exit_seat(true)
	driver_demo = false
	monster.set_physics_process("--hold-at-top" not in OS.get_cmdline_user_args())
	replay = true
	elapsed = 0.0
	side_route = false
	player._exit_climb_to_normal()
	var ladder := rv.get_node_or_null("RoofLadder") as RVLadder
	if ladder == null: return
	player.global_position = ladder.climb_point(0.0) - Vector3.UP * 0.24
	player.rotation.y = ladder.global_rotation.y
	player.velocity = Vector3.ZERO
	player.rv_support.clear()
	# The player now uses the cabin ladder; monsters retain their wall route.
	if rv.to_local(monster.global_position).y < 0.0:
		monster.global_position.y = rv.global_position.y - .2
		monster.velocity = Vector3.ZERO
	# Keep the target alive long enough to inspect support and then press F5.
	player.max_player_health = 10000.0
	player.current_player_health = 10000.0
	player.grab_control.immunity = 10000.0
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
			Input.action_release("move_back")
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
			Input.action_release("move_back")
			player.enter_seat_mode(rv.get_node("DriverSeat"))
			observer.current = true
		KEY_F6:
			cabin_view = not cabin_view
			observer.current = true
		KEY_F7:
			Input.action_release("move_back")
			top_review_time = 0.0
			if is_instance_valid(player.seated_in): player.seated_in.exit_seat(true)
			driver_demo = false
			monster.set_physics_process(false)
			replay = true
			side_route = true
			cabin_view = false
			driving = false
			player_climbed = false
			player._exit_climb_to_normal()
			player.rv_support.clear()
			var ladder: RVLadder = rv.get_node("SideDoorLadder")
			player.global_position = ladder.climb_point(0.0) - Vector3.UP * 0.24
			player.rotation.y = ladder.global_rotation.y
			player.velocity = Vector3.ZERO
			rv.get_node("RightMiddle").restore_angles([-deg_to_rad(100.0)])
			Input.action_press("move_forward")
		KEY_F9:
			_capture_view()
		KEY_F10:
			# Camera/actor setup only: the real placement controller computes
			# every preview pose from its ray. No placement result is injected.
			Input.action_release("move_forward")
			Input.action_release("move_back")
			replay = false
			driving = false
			monster.set_physics_process(false)
			if is_instance_valid(player.seated_in): player.seated_in.exit_seat(true)
			player._exit_climb_to_normal()
			player.rv_support.clear()
			var ladder := rv.get_node_or_null("RoofLadder") as RVLadder
			if ladder == null: return
			player.global_position = ladder.to_global(Vector3(0, -.25, 1.638))
			player.rotation.y = ladder.global_rotation.y
			player.velocity = Vector3.ZERO
			player.camera.look_at(ladder.to_global(Vector3(0, 1.295, -.15)))
			player.camera.current = true
			rv.get_node("RoofLadder").pickup(player)
			player.enter_equipment_placement()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		KEY_R:
			Input.action_release("move_forward")
			get_tree().reload_current_scene()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if not is_instance_valid(monster):
		status.text = "RV CLIMB PLAYGROUND | Monster defeated after release. R: reset"
		return
	# Seat once both have reached the roof, before Raker's grab can kill the
	# player and prevent this optional roof-destruction review from starting.
	if replay and not driver_demo and player_climbed and monster_climbed and player.locomotion_state == player.LocomotionState.NORMAL and monster.locomotion_state == Monster.LocomotionState.NORMAL and "--seat-after-climb" in OS.get_cmdline_user_args():
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
		if player.ladder_transition == player.LadderTransition.TOP and "--hold-at-top" not in OS.get_cmdline_user_args():
			# Deliberate replay input: demonstrate a held-W stop, then neutral,
			# then walking. Production never steers towards a landing point.
			top_review_time += delta
			if top_review_time >= 1.0:
				Input.action_release("move_forward")
				Input.action_release("move_back")
			if top_review_time >= 2.0:
				Input.action_press("move_forward" if side_route else "move_back")
		if driver_demo or (player_climbed and player.locomotion_state == player.LocomotionState.NORMAL):
			Input.action_release("move_forward")
			Input.action_release("move_back")
		# This replay validates carried support, not interception probability.
		# Start movement only after both actors have actually caught a surface.
		driving = not side_route and elapsed > 0.7 and player_climbed and monster_climbed
	if driving:
		rv.position += -rv.basis.z * 4.0 * delta
		rv.rotate_y(0.12 * delta)
	var ladder := rv.get_node_or_null("RoofLadder") as RVLadder
	var cabin_eye := Vector3(.5, 1.8, 3.0)
	var cabin_target := rv.to_global(Vector3(-1.05, 1.65, 0))
	if ladder != null:
		cabin_eye = Vector3(-signf(ladder.position.x) * .5, 1.8, ladder.position.z + 3.0)
		cabin_target = ladder.climb_point(1.15)
	observer.position = rv.to_global(cabin_eye if cabin_view else (Vector3(6, 2, 3) if side_route else Vector3(8, 6, 8)))
	observer.look_at(cabin_target if cabin_view else rv.to_global(Vector3(0, 1.5, 0)))
	status.text = "RV LADDER PLAYGROUND | Player: wall ladder / Monster: wall climb\nF2: move/stop | F3: roof ladder | F4: camera | F5: roof attack\nF6: cabin | F7: side ladder | F9: capture | F10: wall placement | R: reset\nPlayer: %s  y=%.2f | Monster: %s  y=%.2f\nRV motion: %s | roof HP: %s" % [
		player.LocomotionState.keys()[player.locomotion_state], rv.to_local(player.global_position).y,
		monster.LocomotionState.keys()[monster.locomotion_state], rv.to_local(monster.global_position).y,
		str(driving), _roof_health_label()]

func _roof_health_label() -> String:
	var health := 0.0
	var destroyed := 0
	var count := 0
	for name in ["Ceiling", "RoofFront", "RoofMiddle", "RoofRear"]:
		var panel := rv.get_node_or_null(NodePath(name))
		if panel == null: continue
		count += 1
		if panel.is_destroyed: destroyed += 1
		else: health += panel.current_health
	return "DESTROYED (%d/%d)" % [destroyed, count] if destroyed > 0 else str(health)

func _exit_tree() -> void:
	Input.action_release("move_forward")
	Input.action_release("move_back")

func _capture_view() -> void:
	var label := "cabin" if cabin_view else ("side" if side_route else "roof")
	if _roof_health_label().begins_with("DESTROYED"): label += "-destroyed"
	await RenderingServer.frame_post_draw
	var path := "res://docs/validation/images/2026-10-06-rv-ladder-transition-%s.png" % label
	get_viewport().get_texture().get_image().save_png(path)
	print("LADDER_CAPTURE ", path)
