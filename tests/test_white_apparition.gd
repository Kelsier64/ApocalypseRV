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
	var lethal_contacts := 0
	var survival := PlayerSurvival.new()

	func is_gameplay_input_blocked() -> bool:
		return blocked

	func is_grabbed() -> bool:
		return grabbed

	func drain_san(amount: float) -> void:
		survival.drain_san(amount)

	func execution_contact_position() -> Vector3:
		return to_global(Vector3.UP * 1.55)

	func kill() -> void:
		lethal_contacts += 1
		is_player_dead = true

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
	_check_drain_rates()
	await _check_encounter()
	if _failures.is_empty():
		print("PASS: White apparition emergence, distance-based gaze drain, relocation, and despawn")
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

func _check_drain_rates() -> void:
	for sample: Vector2 in [Vector2(0, 220), Vector2(8, 100), Vector2(15, 50), Vector2(25, 15), Vector2(40, 5.859375)]:
		_check(is_equal_approx(Apparition._san_drain_rate(sample.x), sample.y), "SAN drain is %.3f per second at %.1f m" % [sample.y, sample.x])
	var previous := Apparition._san_drain_rate(0.0)
	for distance in range(1, 121):
		var rate := Apparition._san_drain_rate(float(distance))
		_check(rate > 0.0 and rate < previous, "SAN drain remains positive and falls with distance at %d m" % distance)
		previous = rate

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
	var player_shape := _box(player, Vector3(0, 1.55, 0), Vector3.ONE)
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
	_check(apparition._can_confirm(player.camera, chest + Vector3.FORWARD * 30.0, head + Vector3.FORWARD * 30.0), "Clear center gaze beyond 40 m can confirm")
	var camera_far := player.camera.far
	player.camera.far = 39.0
	_check(not apparition._can_confirm(player.camera, chest + Vector3.FORWARD * 30.0, head + Vector3.FORWARD * 30.0), "The camera far plane still bounds gaze")
	_check(not apparition._find_emergence(player.camera, true).is_finite(), "The far spawn band respects the camera far plane")
	player.camera.far = camera_far
	var fog := Environment.new()
	fog.fog_enabled = true
	fog.fog_mode = Environment.FOG_MODE_DEPTH
	fog.fog_density = 1.0
	fog.fog_depth_end = 39.0
	player.camera.environment = fog
	_check(not apparition._find_emergence(player.camera, true).is_finite(), "Opaque depth fog bounds distant emergence")
	_check(apparition._find_emergence(player.camera, false).is_finite(), "Near emergence still fits before opaque depth fog")
	player.camera.environment = null
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

	_check_spawn_bands(apparition, player.camera)
	var edge_chest := player.camera.project_position(Vector2(1288, 360), 15.0)
	_check(not player.camera.is_position_in_frustum(edge_chest), "Edge fixture puts the chest just outside the viewport")
	_check(not apparition._body_outside_view(edge_chest - Apparition.CHEST, player.camera.get_frustum()), "An offscreen chest can still leave part of the silhouette in view")

	apparition._time_left = 0.0
	apparition._physics_process(1.0 / 60.0)
	_check(apparition._phase == Apparition.Phase.VISIBLE and apparition.get_node("Visual").is_visible_in_tree(), "An emergence is active on its first tick")
	_check(apparition._body_outside_view(apparition.global_position, player.camera.get_frustum()), "An emergence starts entirely outside the current view")
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
	await _check_lethal_pursuit(apparition, player, world)
	await _check_seated_contact(apparition, player, player_shape, world)
	viewport.free()

func _check_spawn_bands(apparition: Apparition, camera: Camera3D) -> void:
	var frustum := camera.get_frustum()
	for attempt in 8:
		var near := apparition._find_emergence(camera, false)
		var near_distance := camera.global_position.distance_to(near + Apparition.CHEST)
		_check(near_distance >= 15.0 and near_distance <= 25.0, "Near emergence is between 15 m and 25 m")
		_check(near.is_finite() and apparition._body_outside_view(near, frustum), "Near emergence is entirely offscreen")
		var distant := apparition._find_emergence(camera, true)
		_check(distant.is_finite() and camera.global_position.distance_to(distant + Apparition.CHEST) >= 40.0, "Far emergence starts at 40 m")
		_check(distant.is_finite() and apparition._body_outside_view(distant, frustum), "Far emergence is entirely offscreen")

func _check_confirmed_encounter(apparition: Apparition, player: Survivor, world: Node3D) -> void:
	var camera := player.camera
	var visual = apparition.get_node("Visual")
	var distant := Vector3(0.0, 0.04, -45.0)
	apparition.global_position = distant
	camera.look_at(apparition.to_global(Apparition.CHEST))
	var distance := camera.global_position.distance_to(distant + Apparition.CHEST)
	var san := player.survival.san
	apparition._update_visible(camera, 0.5)
	_check(is_equal_approx(player.survival.san, san - Apparition._san_drain_rate(distance) * 0.5), "Centered confirmed gaze drains SAN at 45 m")
	var confirmed_position := Vector3(0.0, 0.04, -15.0)
	apparition.global_position = confirmed_position
	apparition._appearance_origin = confirmed_position
	camera.look_at(apparition.to_global(Apparition.CHEST))
	distance = camera.global_position.distance_to(confirmed_position + Apparition.CHEST)
	san = player.survival.san
	apparition._update_visible(camera, 1.5)
	_check(is_equal_approx(player.survival.san, san - Apparition._san_drain_rate(distance) * 1.5), "Confirmed SAN drain uses the fixed chest distance")
	san = player.survival.san
	var pose: PackedVector3Array = visual.gaze_points()
	visual._process(0.25)
	_check(visual.gaze_points() != pose, "The drain fixture advances the apparition pose")
	apparition._update_visible(camera, 1.5)
	_check(is_equal_approx(player.survival.san, san - Apparition._san_drain_rate(distance) * 1.5) and player.survival.san < 0.0, "Moving gaze anchors leave the drain rate fixed and SAN can go below zero")
	san = player.survival.san
	world.set_meta("checkpoint_staging", true)
	apparition._physics_process(1.0)
	_check(player.survival.san == san, "Staged simulation cannot drain SAN")
	world.remove_meta("checkpoint_staging")

	var chest: Vector3 = visual.gaze_points()[0]
	camera.look_at(chest)
	camera.rotate_y(deg_to_rad(33.0))
	_check(camera.is_position_in_frustum(chest) and not apparition._point_in_frame(camera, chest, Apparition.CENTER), "Peripheral fixture places the chest in frame outside the center")
	apparition._physics_process(1.0 / 60.0)
	var departure := apparition.global_position
	_check(departure.z > confirmed_position.z and departure.distance_to(confirmed_position) < 0.1 and player.survival.san == san, "The apparition advances in peripheral view without teleporting or draining SAN")
	camera.look_at(chest)
	camera.rotate_y(PI)
	apparition._physics_process(1.0 / 60.0)
	var destination := apparition.global_position
	chest = visual.gaze_points()[0]
	_check(destination.distance_to(departure) >= 10.0, "Leaving the frame teleports at least 10 m on the first tick")
	_check(apparition._body_outside_view(destination, camera.get_frustum()) and not camera.is_position_in_frustum(chest), "The teleport cannot introduce the apparition into the frame")
	apparition._physics_process(0.1)
	var unseen_position := apparition.global_position
	_check(unseen_position.length() < destination.length() and unseen_position.distance_to(destination) < 0.3 and player.survival.san == san, "The apparition advances out of view without another teleport or SAN drain")
	camera.look_at(visual.gaze_points()[0])
	distance = camera.global_position.distance_to(unseen_position + Apparition.CHEST)
	apparition._physics_process(0.1)
	var watched_position := apparition.global_position
	_check(watched_position.length() < unseen_position.length(), "The apparition keeps advancing while watched directly")
	_check(is_equal_approx(player.survival.san, san - Apparition._san_drain_rate(distance) * 0.1), "Looking back resumes drain on the first tick")
	san = player.survival.san
	camera.rotate_y(PI)
	apparition._physics_process(1.0 / 60.0)
	_check(apparition.global_position.distance_to(watched_position) >= 10.0 and player.survival.san == san, "Looking away after reacquiring the apparition triggers another jump without draining SAN")
	camera.look_at(visual.gaze_points()[0])
	apparition._physics_process(0.0)
	await _check_cover_despawn(apparition, player, world)
	await _check_look_away_despawn(apparition, player, world)

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

func _check_cover_despawn(apparition: Apparition, player: Survivor, world: Node3D) -> void:
	var camera := player.camera
	var anchors: PackedVector3Array = apparition.get_node("Visual").gaze_points()
	var chest := anchors[0]
	var head := anchors[1]
	var start := apparition.global_position
	var san := player.survival.san
	var occluder := _static_box(world, camera.global_position.lerp(head, 0.5), Vector3.ONE * 0.08)
	await physics_frame
	await physics_frame
	_check(not apparition._can_confirm(camera, chest, head), "Occluder blocks the centered head ray")
	apparition._update_visible(camera, Apparition.COVER_DESPAWN_SECONDS + 1.0)
	_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible and player.survival.san == san, "A clear chest alone keeps the apparition visible without rapid drain")
	var chest_occluder := _static_box(world, camera.global_position.lerp(chest, 0.5), Vector3.ONE * 0.08)
	await physics_frame
	await physics_frame
	camera.rotate_y(deg_to_rad(33.0))
	apparition._update_visible(camera, Apparition.COVER_DESPAWN_SECONDS - 0.11)
	_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible and player.survival.san == san, "Full cover starts the grace period without draining SAN")
	_check(apparition.global_position == start, "Full cover prevents a pending peripheral relocation")
	camera.look_at(chest)
	occluder.position.y += 1.0
	await physics_frame
	await physics_frame
	apparition._update_visible(camera, 0.2)
	occluder.position.y -= 1.0
	await physics_frame
	await physics_frame
	apparition._update_visible(camera, Apparition.COVER_DESPAWN_SECONDS - 0.11)
	_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible, "Breaking full cover restarts the three-second timer")
	player.in_ui_mode = true
	apparition._physics_process(4.0)
	player.in_ui_mode = false
	player.grabbed = true
	apparition._physics_process(4.0)
	player.grabbed = false
	_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible and player.survival.san == san, "Ineligible cameras pause the cover timer and drain")
	apparition._update_visible(camera, 0.09)
	_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible, "The apparition remains present just before three seconds of cover")
	apparition._physics_process(0.03)
	_check(apparition._phase == Apparition.Phase.HIDDEN and not apparition.visible and player.survival.san == san, "Three seconds of full cover trigger abrupt despawn")
	_check(apparition._time_left >= 25.0 and apparition._time_left <= 40.0, "Despawn starts a new 25–40 second emergence wait")
	occluder.queue_free()
	chest_occluder.queue_free()
	await physics_frame
	await physics_frame

func _check_look_away_despawn(apparition: Apparition, player: Survivor, world: Node3D) -> void:
	var camera := player.camera
	# Occupy both of the closest candidate points without covering the original.
	var blockers: Array[StaticBody3D] = []
	for angle: float in [-60.0, 60.0]:
		var candidate := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle)) * 12.0
		blockers.append(_static_box(world, candidate + Vector3.UP * 0.25, Vector3.ONE))
	await physics_frame
	await physics_frame
	for distance: float in [4.5, 15.0, 45.0]:
		var start := Vector3(0.0, 0.04, -distance)
		camera.look_at(start + Apparition.CHEST)
		apparition._time_left = 0.0
		apparition._physics_process(1.0 / 60.0)
		apparition.global_position = start
		apparition._update_visible(camera, 0.61)
		_check(apparition._phase == Apparition.Phase.CONFIRMED, "The relocation fixture confirms with clear chest and head rays")
		var san := player.survival.san
		camera.rotate_y(PI)
		var tick := 1.0 / 60.0
		apparition._physics_process(tick)
		var end := apparition.global_position
		var bearing_change := start.slide(Vector3.UP).angle_to(end.slide(Vector3.UP))
		_check(end.distance_to(start) >= 10.0 and bearing_change >= deg_to_rad(59.0), "Turning away from %.1f m immediately produces a large change in position and bearing" % distance)
		_check(apparition._body_outside_view(end, camera.get_frustum()), "Turning away cannot cause an apparition to enter the current view")
		_check(is_equal_approx(end.y, start.y), "The teleport ends on the ground")
		for blocker in blockers:
			_check(end.distance_to(blocker.position) > 1.0, "The teleport skips obstructed destinations")
		apparition._update_visible(camera, 29.99 - tick)
		_check(apparition._phase == Apparition.Phase.CONFIRMED and apparition.visible and player.survival.san == san, "Looking away preserves SAN and keeps the apparition present just before 30 seconds")
		_check(apparition.global_position == end, "Relocation does not repeat during the look-away")
		apparition._physics_process(0.03)
		_check(apparition._phase == Apparition.Phase.HIDDEN and not apparition.visible and player.survival.san == san, "30 seconds of continuous look-away trigger abrupt despawn")

func _check_lethal_pursuit(apparition: Apparition, player: Survivor, world: Node3D) -> void:
	player.is_player_dead = false
	apparition.configure(player)
	player.camera.make_current()
	player.camera.look_at(Vector3(0, 1.55, 1))
	apparition._physics_process(0.0)
	apparition._time_left = 0.0
	apparition._physics_process(0.0)
	apparition.global_position = Vector3(0, 0.04, -2.0)
	_check(apparition._phase == Apparition.Phase.VISIBLE, "The lethal pursuit fixture starts unconfirmed")
	var wall := _static_box(world, Vector3(0, 1.5, -0.65), Vector3(8, 3, 0.08))
	await physics_frame
	await physics_frame
	for tick in 60:
		apparition._physics_process(1.0 / 60.0)
	_check(apparition.global_position.z > -2.0 and apparition.global_position.z < -1.1, "The unseen apparition advances up to the wall")
	_check(not player.is_player_dead, "A solid wall blocks lethal contact")
	wall.queue_free()
	await physics_frame
	await physics_frame
	for tick in 60:
		apparition._physics_process(1.0 / 60.0)
	_check(player.is_player_dead and player.lethal_contacts == 1, "An unseen, unconfirmed apparition kills exactly once on body contact")
	_check(apparition._phase == Apparition.Phase.HIDDEN and not apparition.visible, "Lethal contact clears the encounter")

func _check_seated_contact(apparition: Apparition, player: Survivor, player_shape: CollisionShape3D, world: Node3D) -> void:
	player.is_player_dead = false
	var seat := Seat.new()
	seat.seat_camera = player.camera
	world.add_child(seat)
	player.seated_in = seat
	player_shape.disabled = true
	var panel := _static_box(world, Vector3(0, 1.5, -0.14), Vector3(2, 3, 0.08))
	await physics_frame
	await physics_frame
	apparition._physics_process(0.0)
	apparition._time_left = 0.0
	apparition._physics_process(0.0)
	apparition.global_position = Vector3(0, 0.04, -0.64)
	apparition._physics_process(1.0 / 60.0)
	_check(not player.is_player_dead, "A solid panel blocks the seated torso contact even within reach")
	panel.queue_free()
	await physics_frame
	await physics_frame
	apparition._physics_process(1.0 / 60.0)
	_check(player.is_player_dead and player.lethal_contacts == 2, "A physically exposed seated torso can be touched without a locomotion capsule")

func _static_box(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	parent.add_child(body)
	_box(body, Vector3.ZERO, size)
	return body

func _box(body: CollisionObject3D, center: Vector3, size: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
	return collision
