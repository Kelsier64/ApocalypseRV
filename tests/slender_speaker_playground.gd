extends Node3D
## Live production AI and real wheel-powered RV. Only starting layouts/input
## differ by mode; acquisition, animation, ownership, cuts and death stay live.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const PLAYER := preload("res://player/player.tscn")
const RV := preload("res://rv/new_rv.tscn")
const MODE_NAMES := ["", "First-person execution", "Wheel-driven straight chase", "Wheel-driven bend chase", "One-panel smash", "Moving RV one-panel smash", "Steady cruise / wider gap"]
var actors: Node3D
var giant: SlenderSpeaker
var player: CharacterBody3D
var rv: Chassis
var observer: Camera3D
var hud: Label
var nav_region: NavigationRegion3D
var giant_map: RID
var mode := 1
var generation := 0
var elapsed := 0.0
var running := false
var paused := false
var headless_check := false
var capture_requested := false
var capture_directory := ""
var capture_pending := false
var capture_time := 0.0
var captured_frames := 0
var capture_files: Array[Dictionary] = []
var capture_sources: Dictionary = {}
var last_phase := -1
var phase_seen: Dictionary = {}
var execution_seen := false
var death_seen := false
var execution_music_seen := false
var max_player_height := 0.0
var max_giant_speed := 0.0
var vehicle_start := Vector3.ZERO
var vehicle_distance := 0.0
var giant_distance := 0.0
var giant_start := Vector3.ZERO
var broken_before := 0
var observer_enabled := false
var completed := false
var recovery_started := -1.0
var previous_yaw := 0.0
var previous_giant_speed := 0.0
var fast_yaw_rate := 0.0
var near_yaw_rate := 0.0
var chase_samples: Array[Dictionary] = []
var next_chase_sample := 0.0
var vehicle_body_contacts := 0
var moving_attack_distance := 0.0
var moving_recovery_distance := 0.0
var previous_giant_position := Vector3.ZERO
var peak_follow_braking := 0.0
var first_braking_gap := -1.0

func _ready() -> void:
	get_window().title = "ApocalypseRV - Slender Speaker Runtime"
	set_meta("entity_domain", true)
	actors = WorldEntities.get_container(self)
	_build_environment()
	await _build_navigation_forest()
	observer = Camera3D.new()
	observer.far = 1000.0
	observer.fov = 60.0
	add_child(observer)
	var canvas := CanvasLayer.new()
	canvas.layer = 40
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(16, 130)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(hud)
	var arguments := OS.get_cmdline_user_args()
	headless_check = "--headless-check" in arguments
	capture_requested = "--capture" in arguments
	for argument in arguments:
		if argument.begins_with("--mode="): mode = clampi(int(argument.get_slice("=", 1)), 1, 6)
	if capture_requested:
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(1440, 900)
	await select_mode(mode)

func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("24313b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a1b3c0")
	environment.environment.ambient_light_energy = .65
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)

func _build_navigation_forest() -> void:
	giant_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(giant_map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(giant_map, .275)
	NavigationServer3D.map_set_active(giant_map, true)
	nav_region = NavigationRegion3D.new()
	var nav := NavigationMesh.new()
	nav.agent_height = 15.0
	nav.agent_radius = 1.1
	nav.agent_max_climb = .5
	nav.cell_size = .275
	nav.cell_height = .25
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_region.navigation_mesh = nav
	add_child(nav_region)
	nav_region.set_navigation_map(giant_map)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(150, .3, 700)
	collision.shape = shape
	floor_body.add_child(collision)
	nav_region.add_child(floor_body)
	floor_body.position = Vector3(0, -.15, -275)
	var surface := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(150, 700)
	surface.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("53564a")
	floor_material.albedo_texture = load("res://assets/materials/industrial/forest_floor.png")
	floor_material.uv1_scale = Vector3(35, 160, 1)
	floor_material.roughness = 1.0
	surface.material_override = floor_material
	floor_body.add_child(surface)
	surface.position.y = .151
	var rng := RandomNumberGenerator.new()
	rng.seed = 9102026
	for index in 72:
		var tree := MeshInstance3D.new()
		tree.mesh = ForestMeshes.tree(index % 6)
		tree.position = Vector3(rng.randf_range(22, 68) * (-1 if index % 2 else 1), 0, rng.randf_range(-560, 45))
		tree.scale = Vector3(3.1, rng.randf_range(13, 21), 3.1)
		tree.rotation.y = rng.randf_range(-PI, PI)
		nav_region.add_child(tree)
		var trunk := StaticBody3D.new()
		var trunk_collision := CollisionShape3D.new()
		var trunk_shape := CylinderShape3D.new()
		trunk_shape.radius = .45
		trunk_shape.height = 16.0
		trunk_collision.shape = trunk_shape
		trunk.add_child(trunk_collision)
		nav_region.add_child(trunk)
		trunk.position = tree.position + Vector3.UP * 8.0
	nav_region.bake_navigation_mesh(false)
	for frame in 60:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(giant_map) > 0: break
	print("SLENDER_RUNTIME giant_nav_iteration=%d polygons=%d agent_height=15 radius=1.1" % [NavigationServer3D.map_get_iteration_id(giant_map), nav.get_polygon_count()])

func select_mode(next: int) -> void:
	generation += 1
	var ticket := generation
	running = false
	get_tree().paused = false
	paused = false
	for child in actors.get_children(): child.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	if ticket != generation: return
	mode = next
	elapsed = 0.0
	completed = false
	recovery_started = -1.0
	fast_yaw_rate = 0.0
	near_yaw_rate = 0.0
	previous_giant_speed = 0.0
	chase_samples.clear()
	next_chase_sample = 0.0
	vehicle_body_contacts = 0
	moving_attack_distance = 0.0
	moving_recovery_distance = 0.0
	peak_follow_braking = 0.0
	first_braking_gap = -1.0
	last_phase = -1
	phase_seen.clear()
	execution_seen = false
	death_seen = false
	execution_music_seen = false
	max_player_height = 0.0
	max_giant_speed = 0.0
	vehicle_distance = 0.0
	giant_distance = 0.0
	player = null
	rv = null
	giant = null
	capture_time = 0.0
	captured_frames = 0
	capture_files.clear()
	capture_directory = "res://.godot/slender-runtime-captures/mode-%d-%d" % [mode, roundi(Time.get_unix_time_from_system() * 1000)]
	if capture_requested and DisplayServer.get_name() != "headless": DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_directory))
	player = PLAYER.instantiate()
	actors.add_child(player)
	if mode == 1:
		player.global_position = Vector3(0, .05, -2.5)
		player.rotation.y = PI
		player.camera.rotation.x = deg_to_rad(-65)
		player.camera.make_current()
		observer_enabled = false
	else:
		var vehicle: Node3D = RV.instantiate()
		actors.add_child(vehicle)
		vehicle.position = Vector3(0, 1.8, -14 if mode in [4, 5] else -25)
		rv = vehicle.get_node("Chassis")
		rv.allow_test_controls = true
		rv.handbrake = true
		for frame in 100:
			await get_tree().physics_frame
			if ticket != generation: return
		player.global_position = rv.to_global(Vector3(0, .6, -3))
		var seat: Node3D = rv.get_node("DriverSeat")
		seat.interact_hold(player)
		if seat.current_driver != player:
			push_error("SLENDER_RUNTIME production driver seat entry failed")
			rv.get_parent().queue_free()
			return
		rv.gear = 2
		rv.set_engine_running(true)
		rv.handbrake = false
		rv.control_override = {"throttle": 1.0, "steering": 0.0}
		vehicle_start = rv.global_position
		broken_before = _broken_panels()
		observer_enabled = true
		observer.make_current()
	giant = GIANT.instantiate()
	actors.add_child(giant)
	giant.global_position = Vector3(0, .02, 0)
	giant.set_giant_navigation_map(giant_map)
	giant_start = giant.global_position
	previous_giant_position = giant.global_position
	previous_yaw = giant.rotation.y
	capture_sources = _source_hashes()
	running = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if observer_enabled else Input.MOUSE_MODE_CAPTURED)
	print("SLENDER_RUNTIME_READY mode=%d %s capture=%s" % [mode, MODE_NAMES[mode], capture_directory])

func _physics_process(delta: float) -> void:
	if not running or paused or not is_instance_valid(giant): return
	elapsed += delta
	var yaw_rate := rad_to_deg(absf(wrapf(giant.rotation.y - previous_yaw, -PI, PI))) / maxf(delta, .0001)
	if previous_giant_speed > 7.0: fast_yaw_rate = maxf(fast_yaw_rate, yaw_rate)
	else: near_yaw_rate = maxf(near_yaw_rate, yaw_rate)
	previous_yaw = giant.rotation.y
	var speed_change := (giant.velocity.slide(Vector3.UP).length() - previous_giant_speed) / delta
	if is_instance_valid(rv) and giant.phase in [SlenderSpeaker.Phase.CHASE, SlenderSpeaker.Phase.SMASH, SlenderSpeaker.Phase.RECOVER]:
		peak_follow_braking = maxf(peak_follow_braking, -speed_change)
		if first_braking_gap < 0.0 and speed_change < -.2 and previous_giant_speed > rv.road_speed() + .5:
			first_braking_gap = giant._follow_plan.get("clearance", -1.0)
	previous_giant_speed = giant.velocity.slide(Vector3.UP).length()
	var travel := giant.global_position.distance_to(previous_giant_position)
	previous_giant_position = giant.global_position
	if giant.phase == SlenderSpeaker.Phase.SMASH: moving_attack_distance += travel
	if giant.phase == SlenderSpeaker.Phase.RECOVER and giant._recovery_source == SlenderSpeaker.Phase.SMASH: moving_recovery_distance += travel
	for contact in giant.get_slide_collision_count():
		if RVConnection.resolve(giant.get_slide_collision(contact).get_collider()) == rv and is_instance_valid(rv): vehicle_body_contacts += 1
	if elapsed >= next_chase_sample:
		next_chase_sample += .1
		chase_samples.append({"time": elapsed, "phase": SlenderSpeaker.Phase.keys()[int(giant.phase)], "speed_kmh": previous_giant_speed * 3.6, "yaw_deg_per_sec": yaw_rate, "rv_speed_kmh": rv.road_speed() * 3.6 if is_instance_valid(rv) else 0.0, "clearance_m": giant._follow_plan.get("clearance", -1.0), "relative_speed_mps": giant._follow_plan.get("relative_speed", -1.0), "gait_phase": giant._gait_phase})
		chase_samples.back()["acceleration_mps2"] = speed_change
		chase_samples.back()["pelvis_height_m"] = giant._bone_position("pelvis").y - giant.global_position.y
	phase_seen[int(giant.phase)] = true
	max_giant_speed = maxf(max_giant_speed, giant.velocity.slide(Vector3.UP).length())
	giant_distance = maxf(giant_distance, giant.global_position.distance_to(giant_start))
	if int(giant.phase) != last_phase:
		last_phase = int(giant.phase)
		if giant.phase == SlenderSpeaker.Phase.RECOVER and recovery_started < 0.0: recovery_started = elapsed
		print("SLENDER_RUNTIME_PHASE t=%.3f phase=%s player=%s contact=%s giant=%s correction=%s hands=%s/%s" % [elapsed, SlenderSpeaker.Phase.keys()[last_phase], player.global_position, player.execution_contact_position(), giant.global_position, giant._grab_correction, giant.visual.bone_world("hand.R").origin, giant.visual.bone_world("hand.L").origin])
		if elapsed < .1:
			for index in giant.get_slide_collision_count():
				var hit := giant.get_slide_collision(index)
				print("SLENDER_RUNTIME initial_slide=", hit.get_collider(), " normal=", hit.get_normal(), " point=", hit.get_position())
	if is_instance_valid(player):
		execution_seen = execution_seen or player.is_executing()
		death_seen = death_seen or player.is_player_dead
		max_player_height = maxf(max_player_height, player.global_position.y)
		if player.is_executing(): execution_music_seen = execution_music_seen or giant.execution_music.playing
	if is_instance_valid(rv):
		vehicle_distance = maxf(vehicle_distance, rv.global_position.distance_to(vehicle_start))
		var steering := .35 if mode == 3 and elapsed > 4.0 and elapsed < 10.0 else 0.0
		var driving := not (mode == 4 and phase_seen.has(int(SlenderSpeaker.Phase.CONFIRM)))
		var throttle := clampf(.65 + (18.0 - rv.road_speed()) * .12, 0.0, 1.0)
		if mode == 6: throttle = clampf((8.0 - rv.road_speed()) * .8, 0.0, 1.0)
		rv.control_override = {"throttle": throttle, "steering": steering} if driving else {"brake": 1.0}
		if observer_enabled:
			# Fit both complete actors even when a fast RV opens a long gap.
			# The framing follows physics positions, never moves either actor.
			var giant_center := giant.global_position + Vector3.UP * 7.5
			var rv_center := rv.global_position + Vector3.UP * 1.8
			var midpoint := (giant_center + rv_center) * .5
			var radius := maxf(midpoint.distance_to(giant_center) + 8.0, midpoint.distance_to(rv_center) + 7.0)
			var distance := maxf(32.0, radius * 1.1 / sin(deg_to_rad(observer.fov * .5)))
			var review_direction := Vector3(30, 9, 8) if "--side-review" in OS.get_cmdline_user_args() else Vector3(22, 13, 25)
			observer.global_position = midpoint + review_direction.normalized() * distance
			observer.look_at(midpoint)
	elif observer_enabled:
		observer.global_position = Vector3(17, 10, 14)
		observer.look_at(giant.global_position + Vector3.UP * 8.0)
	hud.text = "SLENDER SPEAKER / %s\n%s  %.2f s  | giant %.1f / 60 km/h  | RV %.1f km/h\nF1 execution · F2 straight chase · F3 bend · F4 smash · F5 moving smash\nF6 camera · F7 pause · F8 capture · R reset · Esc exit" % [MODE_NAMES[mode], SlenderSpeaker.Phase.keys()[int(giant.phase)], elapsed, giant.velocity.slide(Vector3.UP).length() * 3.6, rv.road_speed() * 3.6 if is_instance_valid(rv) else 0.0]
	if mode == 6: hud.text += "\nBody-to-chassis gap: %.2f m  | braking %.2f m/s2" % [float(giant._follow_plan.get("clearance", 0.0)), maxf(0.0, -speed_change)]
	if capture_requested and not completed and DisplayServer.get_name() != "headless" and elapsed >= capture_time and not capture_pending:
		capture_time += 1.0 / 30.0
		capture_pending = true
		_save_frame.call_deferred()
	if not completed and ((mode == 1 and death_seen and elapsed > 6.5) or (mode in [4, 5] and recovery_started >= 0.0 and elapsed > recovery_started + 2.95) or elapsed > (24.0 if mode in [2, 3] else 18.0 if mode == 6 else 14.0)):
		completed = true
		_finish_check()

func _broken_panels() -> int:
	var total := 0
	if not is_instance_valid(rv): return total
	for node in rv.find_children("*", "RigidBody3D", true, false):
		if node is RVStructurePanel and node.is_destroyed: total += 1
	return total

func _finish_check() -> void:
	# Native image writes finish after rendering, so flush the pending frame
	# before publishing its manifest or terminating the fixture.
	while capture_pending: await get_tree().process_frame
	var valid := NavigationServer3D.map_get_iteration_id(giant_map) > 0
	if mode == 1: valid = valid and execution_seen and death_seen and execution_music_seen and max_player_height > 9.0
	elif mode in [2, 3]: valid = valid and vehicle_distance > 20.0 and giant_distance > 10.0 and max_giant_speed > 8.0 and max_giant_speed <= giant.settings.chase_speed + .01 and phase_seen.has(int(SlenderSpeaker.Phase.CHASE)) and fast_yaw_rate <= 45.01 and near_yaw_rate <= 90.01
	elif mode == 4: valid = valid and _broken_panels() == broken_before + 1
	elif mode == 5: valid = valid and _broken_panels() == broken_before + 1 and moving_attack_distance > 1.0 and moving_recovery_distance > 1.0
	if mode in [2, 5, 6]: valid = valid and vehicle_body_contacts == 0 and _broken_panels() > broken_before and moving_attack_distance > 1.0 and moving_recovery_distance > 1.0
	if mode == 6:
		valid = valid and peak_follow_braking <= 2.01 and first_braking_gap > 8.0
		print("SLENDER_GENTLE_APPROACH ", JSON.stringify({"peak_braking_mps2": peak_follow_braking, "first_braking_gap_m": first_braking_gap}))
	print("SLENDER_RUNTIME_CHECK ", JSON.stringify({"mode": mode, "valid": valid, "execution": execution_seen, "death": death_seen, "execution_music": execution_music_seen, "max_player_height": max_player_height, "max_giant_speed": max_giant_speed, "fast_yaw_deg_per_sec": fast_yaw_rate, "near_yaw_deg_per_sec": near_yaw_rate, "vehicle_distance": vehicle_distance, "giant_distance": giant_distance, "broken_panels": _broken_panels(), "phase_seen": phase_seen.keys(), "capture_frames": captured_frames, "vehicle_body_contacts": vehicle_body_contacts, "moving_attack_distance": moving_attack_distance, "moving_recovery_distance": moving_recovery_distance}))
	if capture_requested:
		var file := FileAccess.open(capture_directory.path_join("manifest.json"), FileAccess.WRITE)
		if file != null:
			var sources_after := _source_hashes()
			file.store_string(JSON.stringify({"model_sha256": capture_sources["res://assets/models/slender_speaker/slender_speaker_rigged.glb"], "source_sha256": capture_sources, "source_sha256_after": sources_after, "sources_unchanged": capture_sources == sources_after, "engine": Engine.get_version_info(), "rendering_method": RenderingServer.get_current_rendering_method(), "rendering_driver": RenderingServer.get_current_rendering_driver_name(), "viewport_size": str(get_viewport().get_visible_rect().size), "mode": mode, "valid": valid, "chase_samples": chase_samples, "frames": capture_files}, "\t"))
	if headless_check or "--quit-after-review" in OS.get_cmdline_user_args(): get_tree().quit(0 if valid else 1)

func _source_hashes() -> Dictionary:
	var sources := {}
	for source in ["res://assets/models/slender_speaker/slender_speaker_rigged.glb", "res://enemies/slender_speaker/slender_speaker.gd", "res://enemies/slender_speaker/slender_speaker_settings.gd", "res://enemies/slender_speaker/slender_speaker_vehicle_follow.gd", "res://enemies/slender_speaker/slender_speaker_arm_ik.gd", "res://player/player.gd", "res://player/player_grab.gd", "res://tests/slender_speaker_playground.gd"]:
		sources[source] = FileAccess.get_sha256(source)
	return sources

func _save_frame() -> void:
	var ticket := generation
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or ticket != generation or not running or not is_instance_valid(giant) or DisplayServer.get_name() == "headless":
		capture_pending = false
		return
	var path := capture_directory.path_join("frame_%05d.png" % captured_frames)
	var image := get_viewport().get_texture().get_image()
	if image.save_png(path) == OK:
		capture_files.append({"file": path.get_file(), "time": elapsed, "phase": SlenderSpeaker.Phase.keys()[int(giant.phase)], "player_y": player.global_position.y, "camera": str(get_viewport().get_camera_3d().get_path()), "sha256": FileAccess.get_sha256(path)})
		captured_frames += 1
	capture_pending = false

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode in [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5]: select_mode(event.keycode - KEY_F1 + 1)
	elif event.keycode == KEY_F9: select_mode(6)
	elif event.keycode == KEY_R: select_mode(mode)
	elif event.keycode == KEY_F6:
		observer_enabled = not observer_enabled
		if observer_enabled: observer.make_current()
		elif is_instance_valid(player.seated_in): player.seated_in.seat_camera.make_current()
		else: player.camera.make_current()
	elif event.keycode == KEY_F7:
		paused = not paused
		actors.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	elif event.keycode == KEY_F8:
		capture_requested = true
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_directory))
	elif event.keycode == KEY_ESCAPE: get_tree().quit()

func _exit_tree() -> void:
	if giant_map.is_valid(): NavigationServer3D.free_rid(giant_map)
