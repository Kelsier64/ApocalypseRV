extends "res://tests/slender_speaker_animation_workshop.gd"
## Grab/lift review with production hand sweeps, ownership and body extraction.
## Explicit timeline; no autonomous AI, roof attacks or death events.
## -- --scenario=ground|driver --angle=front|side|hands|pov --quit-after-review
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
var giant: SlenderSpeaker
var scenario := "ground"
var angle := "side"
var review_directory := ""
var reference_chest := Vector3.ZERO
var bend_frames: Array[Dictionary] = []
var review_finished := false
var review_playing := false
var previous_review_time := -1.0
var acquired := false
var retained := false
var source_snapshot: Dictionary = {}
var dropped_light_blocked := false
var capture_fps := 30
var review_tag := "shared-grab"

func _ready() -> void:
	super._ready()
	captures_running = true
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="): scenario = argument.get_slice("=", 1)
		if argument.begins_with("--angle="): angle = argument.get_slice("=", 1)
		if argument == "--lift-joint-review":
			review_tag = "lift-joint"
			capture_fps = 60
	get_window().title = "Slender Speaker - Shared Grab / " + scenario + " / " + angle
	get_window().size = Vector2i(1440, 900)
	review_canvas.hide()
	forest.hide()
	grid_mesh.hide()
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("55595c")
	floor_material.roughness = 1.0
	ground_reference.get_child(1).material_override = floor_material
	var neutral := Environment.new()
	neutral.background_mode = Environment.BG_COLOR
	neutral.background_color = Color("64686b")
	neutral.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	neutral.ambient_light_color = Color.WHITE
	neutral.ambient_light_energy = .55
	neutral.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment_holder.environment = neutral
	for light in review_lights: light.light_color = Color.WHITE
	var canvas := CanvasLayer.new()
	add_child(canvas)
	studio_caption = Label.new()
	studio_caption.position = Vector2(20, 18)
	studio_caption.add_theme_font_size_override("font_size", 22)
	studio_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	studio_caption.add_theme_constant_override("shadow_offset_x", 2)
	studio_caption.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(studio_caption)
	await get_tree().process_frame
	_setup_bend_reference()
	# The removed roof's real mounted light must fall before this review starts.
	# Do not let a workshop freeze turn a detached prop into a permanent ceiling.
	if scenario == "driver":
		for tick in 90: await get_tree().physics_frame
		# A stationary roof light lands in the authored finger path. Verify that
		# it really blocks, then prepare a player-cleared cabin via real pickup.
		# Never exempt loose items from the production collision checks.
		_sample_bend(1.0)
		for hit in giant._grab_blocking_hits:
			if str(hit.node).ends_with("/CabinLightFront"): dropped_light_blocked = true
		dropped_light_blocked = dropped_light_blocked and not player.is_executing()
		if not dropped_light_blocked: capture_errors += 1
		print("REVIEW_DROPPED_LIGHT_BLOCKS=", dropped_light_blocked)
		rv.get_node("DriverSeat").exit_seat(true)
		player.set_physics_process(false)
		for item in get_tree().get_nodes_in_group(Groups.ITEMS):
			if item.name == "CabinLightFront" and item.support_lost:
				print("REVIEW_PICKUP_DROPPED_LIGHT: ", item.pickup(player))
				if not item.is_queued_for_deletion(): capture_errors += 1
		await get_tree().process_frame
		# The light is a two-handed item, so put it down outside before driving.
		player.global_position = Vector3(-8.0, .1, -4.0)
		player.drop_item()
		await get_tree().process_frame
		_setup_bend_reference()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for ui: CanvasLayer in rv_reference.find_children("*", "CanvasLayer", true, false): ui.hide()
	for ui: Control in rv_reference.find_children("*", "Control", true, false): ui.hide()
	for ui: Label3D in rv_reference.find_children("*", "Label3D", true, false): ui.hide()
	review_directory = "res://.godot/slender-" + review_tag + "-review/" + scenario + "_" + angle
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(review_directory))
	for path in [visual.MODEL_PATH, "res://enemies/slender_speaker/slender_speaker.gd", "res://enemies/slender_speaker/slender_speaker_arm_ik.gd", "res://player/player_grab.gd", "res://tests/slender_speaker_bend_review.gd"]:
		source_snapshot[path] = FileAccess.get_sha256(path)
	for frame in range(3 * capture_fps + 1):
		_sample_bend(float(frame) / capture_fps)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := review_directory + "/frame_%03d.png" % frame
		var error := get_viewport().get_texture().get_image().save_png(path)
		if error != OK: capture_errors += 1
		var grip: Vector3 = visual.bone_world("socket_grip_R").origin
		bend_frames.append({"file": path.get_file(), "sha256": FileAccess.get_sha256(path), "time": float(frame) / capture_fps, "clip": sampled_clip, "clip_time": sampled_time, "grip": str(grip), "executing": player.is_executing(), "phase": giant.phase, "blocked": giant._grab_blocked, "chest": str(player.execution_contact_position())})
	retained = player.is_executing() and not player.is_player_dead and player.execution_contact_position().y > 10.0
	for path in source_snapshot:
		if source_snapshot[path] != FileAccess.get_sha256(path):
			capture_errors += 1
			push_error("BEND_REVIEW_SOURCE_CHANGED: " + path)
	if not acquired or not retained:
		capture_errors += 1
		push_error("BEND_REVIEW_FAILED capture=%s retained=%s blockers=%s" % [acquired, retained, giant._grab_blocking_hits])
	var manifest := FileAccess.open(review_directory + "/manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"scenario": scenario, "angle": angle, "fps": capture_fps, "acquired": acquired, "retained": retained, "errors": capture_errors, "dropped_light_blocked_before_pickup": dropped_light_blocked, "source_snapshot": source_snapshot, "scope": "Explicit 60Hz production grab/lift rendered at the manifest sample rate, real physical contact, seat release and swept player extraction. Stops before crush. Driver setup: roof_0 removed, fallen cabin light first blocks the hand, then player exits, picks it up and puts it down outside before re-seating for the recorded clear path. No loose-item collision exemption, autonomous AI or roof attack.", "frames": bend_frames}, "\t"))
	print("BEND_REVIEW_COMPLETE scenario=%s angle=%s frames=%d errors=%d directory=%s" % [scenario, angle, bend_frames.size(), capture_errors, review_directory])
	if "--quit-after-review" in OS.get_cmdline_user_args(): get_tree().quit(0 if capture_errors == 0 else 1)
	review_finished = true
	clock = 3.0

func _process(delta: float) -> void:
	if not review_finished or not review_playing: return
	clock = fposmod(clock + delta, 3.8)
	_sample_bend(minf(clock, 3.0))

func _unhandled_input(event: InputEvent) -> void:
	if not review_finished or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_SPACE:
			review_playing = not review_playing
			if review_playing: clock = 0.0
		KEY_1: angle = "front"
		KEY_2: angle = "side"
		KEY_3: angle = "pov"
		KEY_4: angle = "hands"
		KEY_ESCAPE: get_tree().quit()
	_sample_bend(minf(clock, 3.0))

func _setup_bend_reference() -> void:
	if is_instance_valid(giant):
		giant._cancel_execution("review_restart")
	else: visual.queue_free()
	# Mesh-only workshops disable actor subtrees, removing collision bodies.
	# Register physics objects but drive callbacks on the fixed review timeline.
	player.process_mode = Node.PROCESS_MODE_INHERIT
	rv_reference.process_mode = Node.PROCESS_MODE_INHERIT
	for actor in [player, rv_reference]:
		var nodes: Array[Node] = [actor]
		nodes.append_array(actor.find_children("*", "", true, false))
		for node in nodes:
			node.set_process(false)
			node.set_physics_process(false)
			node.set_process_input(false)
			node.set_process_unhandled_input(false)
			if node is RigidBody3D: node.freeze = true
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.body_collision_shape.disabled = false
	player.collision_layer = 1
	player.collision_mask = 3
	player.grab_control.immunity = 0.0
	player.seated_in = null
	player.get_node("Visuals/Locomotion").driving.clear(player_skeleton)
	player_animation.seek(0.0, true)
	player_animation.advance(0.0)
	if not is_instance_valid(giant):
		giant = GIANT.instantiate()
		add_child(giant)
	giant.transform = Transform3D.IDENTITY
	giant.set_physics_process(false)
	giant.patrol_music.stop()
	visual = giant.visual
	acquired = false
	if scenario == "driver":
		rv_reference.show()
		rv_reference.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.226, 0))
		var roof: RVStructurePanel = rv.get_node("StructureSlots").panel("roof_0")
		roof.take_damage(roof.current_health)
		var seat: Node3D = rv.get_node("DriverSeat")
		seat.current_driver = null
		seat.interact_hold(player)
		if player.seated_in != seat or seat.current_driver != player:
			capture_errors += 1
			push_error("BEND_REVIEW_DRIVER_NOT_SEATED")
		player.get_node("Visuals/Locomotion")._physics_process(0.7)
		player_skeleton.force_update_all_bone_transforms()
		player_chest_local = player.to_local((player_skeleton.global_transform * player_skeleton.get_bone_global_pose(player_chest_bone)).origin)
		player_eye_local = player.to_local((player_skeleton.global_transform * player_skeleton.get_bone_global_pose(player_head_bone)).origin) + player_eye_from_head
		reference_chest = player.to_global(player_chest_local)
		giant.global_position = reference_chest.slide(Vector3.UP) + Vector3(-2.6, 0, 0)
		giant.rotation.y = -PI * 0.5
	else:
		rv_reference.hide()
		player.global_transform = Transform3D(Basis(Vector3.UP, PI), ground_player_position)
		player_chest_local = player.to_local((player_skeleton.global_transform * player_skeleton.get_bone_global_pose(player_chest_bone)).origin)
		reference_chest = player.to_global(player_chest_local)
	# A fixed upward player view makes the approach visible without secretly
	# tracking the bent speaker before capture. The production camera owns lift.
	var forward := (giant.global_position - player.global_position).slide(Vector3.UP).normalized()
	player.camera.global_basis = Basis.from_euler(Vector3(.7, atan2(-forward.x, -forward.z), 0.0))
	giant.target_player = player
	giant._sample("idle_play", 0.0)
	giant._begin_grab()
	previous_review_time = -1.0
	print("BEND_REFERENCE scenario=%s chest=%s giant=%s" % [scenario, reference_chest, giant.global_position])
	camera.make_current()

func _advance_review(time: float) -> void:
	var delta := maxf(0.0, time - maxf(0.0, previous_review_time))
	if giant.phase == SlenderSpeaker.Phase.GRAB:
		if is_instance_valid(player.seated_in): player.seated_in.seat_camera.global_basis = player.camera.global_basis
		giant.phase_elapsed = minf(time, 1.0)
		giant._advance_grab()
		acquired = acquired or player.is_executing()
	elif player.is_executing() and time > previous_review_time:
		giant.phase_elapsed += delta
		if giant.phase == SlenderSpeaker.Phase.HOLD: giant.phase_elapsed = minf(.599, giant.phase_elapsed)
		giant._advance_execution()
		player._physics_process(delta)
		player.grab_control._process(delta)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	previous_review_time = time

func _sample_bend(time: float) -> void:
	if time < previous_review_time - .00001: _setup_bend_reference()
	if previous_review_time < 0.0: _advance_review(0.0)
	# Godot production physics runs at 60 Hz; native video samples at 30 Hz.
	while previous_review_time < time - .00001:
		_advance_review(minf(time, previous_review_time + 1.0 / 60.0))
	sampled_clip = "grab" if giant.phase == SlenderSpeaker.Phase.GRAB else ("lift" if giant.phase == SlenderSpeaker.Phase.LIFT else ("hold" if giant.phase == SlenderSpeaker.Phase.HOLD else "cancelled"))
	sampled_time = giant.phase_elapsed
	var target: Vector3 = visual.global_position + Vector3(0, 7.2, 0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 19.5
	camera.cull_mask = 0xFFFFF
	if angle == "hands":
		target = visual.bone_world("socket_grip_R").origin + Vector3.UP * .2
		camera.size = 4.5
	var direction := giant.global_basis * (Vector3(1, .08, 0) if angle == "side" else Vector3(.35, .1, -1).normalized())
	camera.global_position = target + direction * 32.0
	if angle == "pov":
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 78.0
		camera.near = .015
		camera.cull_mask = player.get_node("Camera3D").cull_mask
		camera.global_transform = player.camera.global_transform
	else: camera.look_at(target, Vector3.UP)
	camera.make_current()
	studio_caption.text = "%s / %s / %s\n%.2f s  |  %s  |  REAL HAND CONTACT / %s" % [review_tag.to_upper(), scenario.to_upper(), angle.to_upper(), time, sampled_clip.to_upper(), "CAPTURED" if player.is_executing() else "REACHING"]
