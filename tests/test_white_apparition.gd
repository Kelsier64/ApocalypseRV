extends SceneTree

const ApparitionScene := preload("res://enemies/white_apparition/white_apparition.tscn")
const Apparition := preload("res://enemies/white_apparition/white_apparition.gd")

class Survivor extends CharacterBody3D:
	var camera: Camera3D
	var seated_in: Node3D
	var in_ui_mode := false
	var is_player_dead := false
	var blocked := false
	var grabbed := false
	var survival := PlayerSurvival.new()

	func is_gameplay_input_blocked() -> bool:
		return blocked

	func is_grabbed() -> bool:
		return grabbed

	func drain_san(amount: float) -> void:
		survival.drain_san(amount)

class Seat extends Node3D:
	var seat_camera: Camera3D

var _failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if ok: return
	_failures.append(label)
	push_error(label)

func _run() -> void:
	_check_visual_motion()
	await _check_encounter()
	if _failures.is_empty():
		print("PASS: White apparition motion, gaze-dependent SAN drain, and unseen despawn")
	quit(0 if _failures.is_empty() else 1)

func _check_visual_motion() -> void:
	var visual = load("res://enemies/white_apparition/white_apparition_visual.gd").new()
	root.add_child(visual)
	visual.set_process(false)
	visual._rng.seed = 2026
	visual.begin_appearance()
	visual.position = Vector3(4, 0, -7)
	visual.rotation.y = 0.6
	visual._clock = 0.0
	var skeleton: Skeleton3D = visual._skeletons[0]
	var feet: Array[int] = [skeleton.find_bone("FootL"), skeleton.find_bone("FootR")]
	var ankles: Array[Vector3] = []
	for foot in feet:
		ankles.append(skeleton.get_bone_global_rest(foot).origin)
	var start_head: Vector3 = visual.gaze_points()[1]
	var max_head_motion := 0.0
	var max_foot_drift := 0.0
	var max_anchor_step := 0.0
	var previous_gaze := PackedVector3Array()
	for phrase in 6:
		visual._phrase = phrase
		visual._phrase_time = 0.0
		visual._phrase_duration = 4.0 if phrase < 5 else 0.22
		# The shudder runs through its full envelope and returns to a sustained phrase.
		for tick in 240:
			visual._process(1.0 / 60.0)
			var gaze: PackedVector3Array = visual.gaze_points()
			if gaze.size() != 2 or not gaze[0].is_finite() or not gaze[1].is_finite():
				_check(false, "Animated gaze anchors stay finite through phrase %d" % phrase)
				visual.free()
				return
			for anchor in previous_gaze.size():
				max_anchor_step = maxf(max_anchor_step, gaze[anchor].distance_to(previous_gaze[anchor]))
			previous_gaze = gaze
			max_head_motion = maxf(max_head_motion, gaze[1].distance_to(start_head))
			for side in feet.size():
				max_foot_drift = maxf(max_foot_drift, skeleton.get_bone_global_pose(feet[side]).origin.distance_to(ankles[side]))
	_check(max_head_motion > 0.3, "Head gaze anchor follows substantial body contortion in world space")
	_check(max_anchor_step < 0.16, "Gaze anchors move without snapping through phrase transitions")
	_check(max_foot_drift < 0.02, "Both ankles remain planted throughout all motion phrases")
	visual.free()

func _check_encounter() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var chunk := ChunkGenerator.new()
	world.add_child(chunk)
	var surface := MeshInstance3D.new()
	surface.name = "Ground"
	chunk.add_child(surface)
	_static_box(surface, Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	var roof := _static_box(world, Vector3(29, 3.0, -14), Vector3(4, 0.4, 4))
	var head_occluder := _static_box(world, Vector3(0, 1.8, -7.5), Vector3(0.4, 0.1, 0.4))
	var player := Survivor.new()
	player.camera = Camera3D.new()
	player.camera.position = Vector3(0, 1.55, 0)
	player.add_child(player.camera)
	_box(player, Vector3(0, 1.55, 0), Vector3.ONE)
	world.add_child(player)
	player.camera.make_current()
	var apparition := ApparitionScene.instantiate() as Apparition
	world.add_child(apparition)
	apparition.set_physics_process(false)
	apparition.get_node("Visual").set_process(false)
	apparition.configure(player)
	apparition._rng.seed = 2026
	await physics_frame
	await physics_frame
	apparition._physics_process(0.0)

	var chest := Vector3(0.0, 1.55, -15.0)
	var head := Vector3(0.0, 2.05, -15.0)
	_check(not apparition._can_confirm(player.camera, chest, head), "Hidden apparitions cannot confirm a sighting")
	apparition.show()
	_check(not apparition._can_confirm(player.camera, chest, head), "Occluding just the head breaks the sighting")
	head_occluder.position.y = 1.55
	await physics_frame
	await physics_frame
	_check(not apparition._can_confirm(player.camera, chest, head), "Occluding just the chest breaks the sighting")
	head_occluder.queue_free()
	await physics_frame
	await physics_frame
	_check(apparition._can_confirm(player.camera, chest, head), "Clear center rays ignore the observer's own collision RID")
	for screen_position in [Vector2(0.71, 0.5), Vector2(0.5, 0.71)]:
		var edge := player.camera.project_position(screen_position * Vector2(viewport.size), 15.0)
		_check(not apparition._can_confirm(player.camera, edge, edge + Vector3.UP * 0.5), "Peripheral horizontal or vertical screen projection does not count")
	_check(not apparition._can_confirm(player.camera, chest - Vector3.FORWARD * 30.0, head - Vector3.FORWARD * 30.0), "Points behind the camera do not count")
	_check(not apparition._can_confirm(player.camera, chest + Vector3.FORWARD * 30.0, head + Vector3.FORWARD * 30.0), "Points beyond the gaze range do not count")
	var space := world.get_world_3d().direct_space_state
	_check(not apparition._grounded_position(space, roof.position, 4.0, 8.0).is_finite(), "A roof cannot support an emergence")
	_check(apparition._grounded_position(space, Vector3(0, 0, -15), 4.0, 8.0).is_finite(), "Streamed ground supports an emergence")

	var other_camera := Camera3D.new()
	world.add_child(other_camera)
	other_camera.make_current()
	_check(apparition._active_player_camera() == null, "An unrelated current camera cannot score for the player")
	var seat := Seat.new()
	seat.seat_camera = other_camera
	world.add_child(seat)
	player.seated_in = seat
	_check(apparition._active_player_camera() == other_camera, "The player's current driving camera is eligible")
	player.seated_in = null
	player.camera.make_current()
	player.in_ui_mode = true
	_check(apparition._active_player_camera() == null, "Player UI excludes gaze")
	player.in_ui_mode = false
	player.blocked = true
	_check(apparition._active_player_camera() == null, "Settings and captured release input exclude gaze")
	player.blocked = false
	player.grabbed = true
	_check(apparition._active_player_camera() == null, "Grab execution views exclude gaze")
	player.grabbed = false
	apparition.hide()

	var start := Vector3(2.5, 0.04, -15.0)
	apparition.global_position = start
	apparition._appearance_origin = start
	var drift_wall := _static_box(world, Vector3(1.6, 1.2, -15.0), Vector3(0.08, 2.4, 2.0))
	await physics_frame
	await physics_frame
	apparition._drift_toward_center(player.camera, 4.0)
	_check(apparition.global_position.is_equal_approx(start), "The drift sweep cannot pass through a wall")
	drift_wall.queue_free()
	await physics_frame
	await physics_frame
	for tick in 90:
		apparition._drift_toward_center(player.camera, 1.0 / 15.0)
	var drift := apparition.global_position - start
	_check(drift.x < -1.9 and drift.x >= -2.0 and is_zero_approx(drift.z), "The drift moves sideways toward center within two metres")
	apparition._appearance_origin = Vector3.INF

	apparition._time_left = 0.0
	apparition._physics_process(1.0 / 60.0)
	_check(apparition._phase == Apparition.Phase.VISIBLE and apparition.get_node("Visual").is_visible_in_tree(), "An emergence is visible on its first tick")
	var target := apparition.to_global(Apparition.CHEST)
	_check(not apparition._point_in_frame(player.camera, target, Apparition.CENTER), "A new appearance starts outside the center")
	var distance := player.camera.global_position.distance_to(target)
	_check(distance >= 10.0 and distance <= 22.0, "Emergence stays at a comfortable distance")
	apparition._time_left = 0.0
	apparition._physics_process(1.0 / 60.0)
	_check(apparition._phase == Apparition.Phase.HIDDEN and not apparition.get_node("Visual").is_visible_in_tree(), "An unconfirmed appearance disappears on the expiry tick")
	_check(player.survival.san == PlayerSurvival.MAX_SAN, "An unseen apparition does not rapidly drain SAN")

	apparition._time_left = 0.0
	apparition._physics_process(1.0 / 60.0)
	_check(apparition._phase == Apparition.Phase.VISIBLE, "The apparition can emerge again after going unseen")
	player.camera.look_at(apparition.to_global(Apparition.CHEST))
	apparition._physics_process(0.59)
	_check(apparition._phase == Apparition.Phase.VISIBLE, "A glance shorter than 0.6 seconds does not confirm")
	player.camera.rotate_y(PI)
	apparition._physics_process(0.01)
	player.camera.look_at(apparition.to_global(Apparition.CHEST))
	apparition._physics_process(0.59)
	_check(apparition._phase == Apparition.Phase.VISIBLE, "An interruption restarts the gaze dwell")
	apparition._physics_process(0.02)
	_check(apparition._phase == Apparition.Phase.CONFIRMED, "The first uninterrupted gaze confirms the apparition")
	var visual = apparition.get_node("Visual")
	var pose: PackedVector3Array = visual.gaze_points()
	visual._process(1.0 / 60.0)
	_check(visual.gaze_points() != pose, "White apparition keeps animating after confirmation")

	await _check_confirmed_encounter(apparition, player, world)
	viewport.free()

func _check_confirmed_encounter(apparition: Apparition, player: Survivor, world: Node3D) -> void:
	var camera := player.camera
	var anchors: PackedVector3Array = apparition.get_node("Visual").gaze_points()
	var chest := anchors[0]
	var head := anchors[1]
	var confirmed_position := apparition.global_position
	camera.look_at(chest)
	var san := player.survival.san
	apparition._physics_process(1.5)
	_check(is_equal_approx(player.survival.san, san - 150.0) and player.survival.san < 0.0, "Centered confirmed gaze drains at 100 SAN per second through zero")
	san = player.survival.san
	world.set_meta("checkpoint_staging", true)
	apparition._physics_process(1.0)
	_check(player.survival.san == san, "Staged simulation cannot drain SAN")
	world.remove_meta("checkpoint_staging")

	camera.rotate_y(PI)
	apparition._physics_process(2.9)
	_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible, "Looking away leaves the apparition visible during the grace period")
	_check(player.survival.san == san, "Looking away immediately stops rapid drain")
	camera.look_at(chest)
	camera.rotate_y(deg_to_rad(40.0))
	_check(camera.is_position_in_frustum(chest) and not apparition._point_in_frame(camera, chest, Apparition.CENTER), "Peripheral fixture places the chest in frame outside the center")
	apparition._physics_process(4.0)
	_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible and player.survival.san == san, "Peripheral visibility prevents despawn without rapidly draining SAN")
	_check(apparition.global_position == confirmed_position, "The confirmed apparition stays in place")
	camera.rotate_y(PI)
	apparition._physics_process(0.2)
	_check(apparition._phase == Apparition.Phase.CONFIRMED, "Peripheral reacquisition restarts the continuous unseen timer")
	camera.look_at(chest)
	apparition._physics_process(0.1)
	_check(is_equal_approx(player.survival.san, san - 10.0), "Looking back resumes rapid drain on the first tick")
	san = player.survival.san

	var occluder := _static_box(world, camera.global_position.lerp(head, 0.5), Vector3.ONE * 0.08)
	await physics_frame
	await physics_frame
	_check(not apparition._can_confirm(camera, chest, head), "Occluder blocks the centered head ray")
	apparition._physics_process(4.0)
	_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible and player.survival.san == san, "A clear chest alone keeps the apparition visible without rapid drain")
	var chest_occluder := _static_box(world, camera.global_position.lerp(chest, 0.5), Vector3.ONE * 0.08)
	await physics_frame
	await physics_frame
	apparition._physics_process(2.9)
	_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible and player.survival.san == san, "Full occlusion starts the grace period and stops rapid drain")
	player.in_ui_mode = true
	apparition._physics_process(4.0)
	player.in_ui_mode = false
	player.grabbed = true
	apparition._physics_process(4.0)
	player.grabbed = false
	_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible and player.survival.san == san, "Ineligible cameras pause the unseen timer and rapid drain")
	apparition._physics_process(0.09)
	_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible, "The apparition remains visible just before three unseen seconds")
	apparition._physics_process(0.02)
	_check(apparition._phase == Apparition.Phase.HIDDEN and not apparition.visible and player.survival.san == san, "Three unseen seconds trigger abrupt despawn")
	_check(apparition._time_left >= 4.0 and apparition._time_left <= 8.0, "Despawn starts a new emergence wait")
	occluder.queue_free()
	chest_occluder.queue_free()
	await physics_frame
	await physics_frame

	apparition._time_left = 0.0
	apparition._physics_process(1.0 / 60.0)
	camera.look_at(apparition.to_global(Apparition.CHEST))
	apparition._physics_process(0.61)
	_check(apparition._phase == Apparition.Phase.CONFIRMED, "A later emergence can be confirmed again")
	san = player.survival.san
	player.is_player_dead = true
	apparition._physics_process(0.01)
	_check(apparition._phase == Apparition.Phase.HIDDEN and not apparition.visible and player.survival.san == san, "Death clears the transient encounter and stops rapid drain")
	var replacement := Survivor.new()
	world.add_child(replacement)
	apparition.configure(replacement)
	apparition._physics_process(1.0)
	_check(replacement.survival.san == PlayerSurvival.MAX_SAN and not apparition.visible, "A different observer never inherits a confirmed sighting")

func _static_box(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	parent.add_child(body)
	_box(body, Vector3.ZERO, size)
	return body

func _box(body: CollisionObject3D, center: Vector3, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
