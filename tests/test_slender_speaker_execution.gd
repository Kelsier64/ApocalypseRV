extends SceneTree
## Production Player ownership, swept extraction, cuts and recovery.
const PLAYER := preload("res://player/player.tscn")
const GRAB_CONTROL := preload("res://player/player_grab.gd")
class FramingCaptor extends Node3D:
	var frame_calls := 0
	var offset := Vector3(3, 1, 5)
	func execution_camera_frame(subject: Node3D) -> Dictionary:
		frame_calls += 1
		var pivot := subject.global_position + Vector3.UP * 1.2
		return {"pivot": pivot, "focus": pivot + Vector3(0, .4, -1), "offset": offset}
class SaveManagerStub extends Node:
	var busy := false
	var active_id := ""
class SaveGeneratorStub extends Node:
	var building := false
class NoDiskStorage extends CheckpointFiles:
	var writes := 0
	func write(_path: String, _data: Dictionary) -> Dictionary:
		writes += 1
		return {"ok": false, "code": "test_no_disk"}
var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
var captor: Node3D
var anchor: Node3D
var face: Node3D
var reasons: Array[String] = []
var body_events := 0

func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
func frames(count: int = 2) -> void:
	for i in count:
		await physics_frame
		await process_frame
func reset() -> void:
	if player.is_grabbed(): player.grab_control.end("test_reset")
	player.ragdoll_control.stop()
	player.is_player_dead = false
	player.grab_control.immunity = 0.0
	player.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0, "transform": Transform3D(Basis.IDENTITY, Vector3(0, .05, 0))})
	player.set_physics_process(false)
	anchor.global_position = player.execution_contact_position()
	face.global_position = Vector3(0, 13.8, -2)
	reasons.clear()

func capture() -> bool:
	anchor.global_position = player.execution_contact_position()
	return player.begin_execution(captor, anchor, face)

func test_ownership_lift_cancel() -> void:
	reset()
	player.add_item("Scrap", false, "res://props/scrap.tscn")
	var inventory_before: Array = player.inventory.items.duplicate(true)
	var held_before: Node3D = player.held_item_node
	var slot_before: int = player.inventory.active_slot
	check(not inventory_before.is_empty() and is_instance_valid(held_before), "Inventory preservation exercise uses a real held Item")
	var near_before: float = player.camera.near
	var fov_before: float = player.camera.fov
	var position_before: Vector3 = player.camera.position
	check(capture(), "Ground capture obtains execution ownership")
	check(player.is_grabbed() and player.is_executing() and player.grab_control.captor == captor, "Shared grab mode has unique giant owner")
	check(not player.submit_struggle() and player.grab_control.presses == 0 and not player.grab_control.hud.visible, "Execution has no SPACE escape or struggle HUD")
	var stranger := Node3D.new()
	world.add_child(stranger)
	check(not player.begin_execution(stranger, anchor, face), "Second captor cannot steal active ownership")
	player.cancel_execution(stranger)
	check(player.is_executing(), "Foreign owner cannot cancel execution")
	var before: Vector3 = player.global_position
	anchor.global_position += Vector3.UP * 8.0
	player._physics_process(1.0 / 60.0)
	var initial_view: Quaternion = player.camera.global_basis.get_rotation_quaternion()
	player.grab_control._process(.1)
	check(rad_to_deg(initial_view.angle_to(player.camera.global_basis.get_rotation_quaternion())) <= 12.01,
		"Execution begins turning toward the face within its angular speed limit")
	check(initial_view.is_equal_approx(player.camera.global_basis.get_rotation_quaternion()),
		"Capture briefly retains the original view before gently guiding it")
	for tick in 180: player.grab_control._process(1.0 / 60.0)
	check(is_equal_approx(player.camera.fov, fov_before) and player.camera.position.is_equal_approx(position_before),
		"Generic execution captor leaves camera FOV and local eye position unchanged")
	check(player.global_position.is_equal_approx(before + Vector3.UP * 8.0), "Player body follows chest anchor without extra gravity drift")
	var direction: Vector3 = (face.global_position - player.camera.global_position).normalized()
	print("EXECUTION_CAMERA_CONVERGENCE " + JSON.stringify({"eye": player.camera.global_position,
		"focus": face.global_position, "forward": -player.camera.global_basis.z,
		"alignment": (-player.camera.global_basis.z).dot(direction)}))
	check((-player.camera.global_basis.z).dot(direction) > .99, "First-person guidance keeps the speaker in view within its comfortable pitch limit")
	var view_before: Transform3D = player.camera.global_transform
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 100)
	player._unhandled_input(motion)
	check(player.camera.global_transform.is_equal_approx(view_before), "Ordinary mouse look cannot rotate the restrained body")
	var previous_mouse_mode := Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var body_before: Transform3D = player.global_transform
	# Headless display cannot capture a pointer; exercise the same motion handler.
	if DisplayServer.get_name() == "headless": player.grab_control._execution_mouse_look(motion)
	else: player.grab_control._input(motion)
	check(not player.camera.global_basis.is_equal_approx(view_before.basis), "Grab input allows looking around the guided view")
	var offset: Vector2 = player.grab_control.execution_look_offset
	for tick in 60: player.grab_control._process(1.0 / 60.0)
	check(player.grab_control.execution_look_offset.is_equal_approx(offset)
		and not player.camera.global_basis.is_equal_approx(view_before.basis),
		"Automatic guidance preserves the survivor's chosen viewing offset")
	motion.relative = Vector2(100000, -100000)
	if DisplayServer.get_name() == "headless": player.grab_control._execution_mouse_look(motion)
	else: player.grab_control._input(motion)
	check(absf(rad_to_deg(player.grab_control.execution_look_offset.x)) <= 25.01
		and absf(rad_to_deg(player.grab_control.execution_look_offset.y)) <= 18.01,
		"Execution mouse look stays inside its yaw and pitch limits")
	check(player.global_transform.is_equal_approx(body_before), "Looking around never changes the restrained body's transform")
	Input.set_mouse_mode(previous_mouse_mode)
	check(player.inventory.items == inventory_before, "Lift preserves inventory and held item state")
	check(player.inventory.active_slot == slot_before and player.held_item_node == held_before, "Lift preserves active slot and the actual held Item instance")
	player.cancel_execution(captor)
	check(not player.is_grabbed() and not player.is_player_dead and player.grab_control.camera == null, "Cancellation safely releases controller and camera")
	check(is_equal_approx(player.camera.near, near_before), "Cancellation restores camera clipping distance")
	check(is_equal_approx(player.camera.fov, fov_before) and player.camera.position.is_equal_approx(position_before),
		"Generic cancellation retains the original camera FOV and position")
	check(player.grab_control.execution_look_offset == Vector2.ZERO, "Cancellation clears execution viewing offsets")
	check(reasons == ["cancelled"], "One cancellation event reaches music/controller owner")
	check(player.inventory.items == inventory_before and player.held_item_node == held_before, "Cancellation retains inventory and held Item identity")
	stranger.queue_free()

func test_execution_framing_cleanup() -> void:
	reset()
	# Keep this custom eye baseline independent of ordinary idle locomotion.
	var locomotion := player.get_node("Visuals/Locomotion")
	var locomotion_was_processing := locomotion.is_physics_processing()
	locomotion.set_physics_process(false)
	var original_position: Vector3 = player.camera.position
	var original_fov: float = player.camera.fov
	var original_near: float = player.camera.near
	var rest_position := original_position + Vector3(.03, .02, -.01)
	player.camera.position = rest_position
	player.camera.fov = 68.0
	player.camera.near = .08
	var eye_basis: Basis = player.camera.global_basis
	var owner := FramingCaptor.new()
	world.add_child(owner)
	owner.position = Vector3(0, 0, -6)
	var grip := Node3D.new()
	owner.add_child(grip)
	grip.global_position = player.execution_contact_position()
	var speaker := Node3D.new()
	owner.add_child(speaker)
	speaker.global_position = Vector3(0, 10, -2)
	check(player.begin_execution(owner, grip, speaker), "Third-person provider obtains execution ownership")
	var observer: Camera3D = player.grab_control.execution_observer
	check(is_instance_valid(observer) and observer != player.camera and observer.current
		and root.get_camera_3d() == observer and not player.camera.current,
		"Provider capture selects a dedicated observer as the actual viewport camera")
	check((observer.cull_mask & PlayerModelVisual.FULL_BODY_LAYER) != 0
		and (observer.cull_mask & PlayerModelVisual.LOCAL_VIEW_LAYER) == 0,
		"Observer shows the full survivor and excludes the local torso copy")
	check(not observer.is_position_behind(player.global_position + Vector3.UP * 1.7)
		and not observer.is_position_behind(player.global_position), "Survivor head and feet are in front of the external camera")
	check(player.camera.position.is_equal_approx(rest_position) and is_equal_approx(player.camera.fov, 68.0)
		and is_equal_approx(player.camera.near, .08) and player.camera.global_basis.is_equal_approx(eye_basis),
		"Third-person capture preserves first-person eye, FOV, clipping and orientation")
	var observer_before: Vector3 = observer.global_position
	grip.global_position += Vector3.UP * 3.0
	player._physics_process(1.0 / 60.0)
	player.grab_control._process(1.0 / 60.0)
	check(observer.global_position.is_equal_approx(observer_before + Vector3.UP * 3.0), "Observer follows the actual swept player lift")
	var body_before: Transform3D = player.global_transform
	var view_before: Transform3D = observer.global_transform
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 100)
	var previous_mouse_mode := Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if DisplayServer.get_name() == "headless": player.grab_control._execution_mouse_look(motion)
	else: player.grab_control._input(motion)
	check(not observer.global_transform.is_equal_approx(view_before), "Restrained mouse input orbits the external camera")
	var orbit: Vector2 = player.grab_control.execution_look_offset
	for tick in 60: player.grab_control._process(1.0 / 60.0)
	check(player.grab_control.execution_look_offset.is_equal_approx(orbit), "Automatic framing retains the chosen orbit")
	motion.relative = Vector2(100000, -100000)
	if DisplayServer.get_name() == "headless": player.grab_control._execution_mouse_look(motion)
	else: player.grab_control._input(motion)
	check(absf(rad_to_deg(player.grab_control.execution_look_offset.x)) <= 25.01
		and absf(rad_to_deg(player.grab_control.execution_look_offset.y)) <= 18.01, "Third-person orbit obeys restrained yaw and pitch limits")
	check(player.global_transform.is_equal_approx(body_before) and player.camera.global_basis.is_equal_approx(eye_basis)
		and player.camera.position.is_equal_approx(rest_position) and is_equal_approx(player.camera.fov, 68.0),
		"Orbit changes neither restrained body nor first-person camera")
	Input.set_mouse_mode(previous_mouse_mode)
	player.cancel_execution(owner)
	check(not player.is_grabbed() and player.grab_control.camera == null and player.grab_control.execution_observer == null
		and observer.is_queued_for_deletion() and player.camera.current, "Cancellation disposes observer and restores player camera ownership")
	check(player.camera.position.is_equal_approx(rest_position) and is_equal_approx(player.camera.fov, 68.0)
		and is_equal_approx(player.camera.near, .08) and player.grab_control.execution_look_offset == Vector2.ZERO,
		"Cancellation preserves nondefault eye baseline and clears orbit")
	var calls_after_cancel := owner.frame_calls
	player.grab_control._process(.1)
	check(owner.frame_calls == calls_after_cancel, "Cancellation stops querying the former framing provider")
	player.set_physics_process(false)
	player.grab_control.immunity = 0.0
	player.camera.fov = 96.0
	check(player.begin_execution(owner, grip, speaker), "Recapture creates a new observer with a new eye baseline")
	observer = player.grab_control.execution_observer
	var pivot: Vector3 = owner.execution_camera_frame(player).pivot
	var clear_distance := observer.global_position.distance_to(pivot)
	# A real wall intersects only the camera corridor, clear of the full body.
	var wall := StaticBody3D.new()
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(8, 8, .1)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	world.add_child(wall)
	wall.global_position = pivot + owner.offset.normalized() * 2.0
	wall.look_at(wall.global_position + owner.offset.normalized(), Vector3.UP)
	await frames()
	player.grab_control._process(1.0 / 60.0)
	var clipped_distance := observer.global_position.distance_to(pivot)
	check(player.is_executing() and clipped_distance > 1.0 and clipped_distance < 1.85 and clipped_distance < clear_distance,
		"Camera sphere sweep stops before a wall without releasing valid body ownership")
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = .17
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, observer.global_position)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	check(player.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "Clipped camera volume remains outside real solids")
	print("EXECUTION_THIRD_PERSON_METRICS " + JSON.stringify({"clear_distance_m": clear_distance, "wall_limited_distance_m": clipped_distance}))
	player.complete_world_transition(Transform3D(Basis.IDENTITY, Vector3(12, .05, 0)))
	check(not player.is_grabbed() and player.grab_control.execution_observer == null and player.camera.current
		and observer.is_queued_for_deletion() and player.camera.position.is_equal_approx(rest_position)
		and is_equal_approx(player.camera.fov, 96.0), "World transition disposes observer and restores its own eye baseline")
	wall.queue_free()
	await frames()
	player.set_physics_process(false)
	player.grab_control.immunity = 0.0
	grip.global_position = player.execution_contact_position()
	check(player.begin_execution(owner, grip, speaker), "Owner removal starts a new third-person execution")
	observer = player.grab_control.execution_observer
	owner.queue_free()
	await frames()
	check(not player.is_grabbed() and player.grab_control.execution_observer == null
		and not is_instance_valid(observer) and player.camera.current, "Removing provider frees observer and returns viewport ownership")
	# Cleanup must respect a camera selected by another system after capture.
	owner = FramingCaptor.new()
	world.add_child(owner)
	grip = Node3D.new()
	owner.add_child(grip)
	grip.global_position = player.execution_contact_position()
	speaker = Node3D.new()
	owner.add_child(speaker)
	speaker.global_position = Vector3(12, 10, -2)
	player.set_physics_process(false)
	player.grab_control.immunity = 0.0
	check(player.begin_execution(owner, grip, speaker), "External camera ownership test begins capture")
	var external := Camera3D.new()
	world.add_child(external)
	external.make_current()
	player.cancel_execution(owner)
	check(external.current and root.get_camera_3d() == external and player.grab_control.execution_observer == null,
		"Cancellation preserves camera ownership selected externally after capture")
	external.queue_free()
	player.camera.make_current()
	player.set_physics_process(false)
	player.grab_control.immunity = 0.0
	check(player.begin_execution(owner, grip, speaker), "Fatal execution begins third-person ownership")
	observer = player.grab_control.execution_observer
	check(player.complete_execution(owner), "Third-person execution completes through ordinary death")
	check(player.is_player_dead and not player.is_grabbed() and player.grab_control.execution_observer == observer
		and player.grab_control.has_execution_death_view() and observer.current and not player.camera.current,
		"Death releases grab ownership while retaining the third-person observer")
	player._respawn()
	check(player.grab_control.execution_observer == null and observer.is_queued_for_deletion() and player.camera.current,
		"Successful respawn clears the death observer and restores first-person view")
	owner.queue_free()
	await frames()
	player.camera.position = original_position
	player.camera.fov = original_fov
	player.camera.near = original_near
	reset()
	locomotion.set_physics_process(locomotion_was_processing)

func test_third_person_world_and_player_removal() -> void:
	reset()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16, 16)
	world.add_child(viewport)
	var owner := FramingCaptor.new()
	viewport.add_child(owner)
	var grip := Node3D.new()
	owner.add_child(grip)
	grip.global_position = player.execution_contact_position()
	var speaker := Node3D.new()
	owner.add_child(speaker)
	speaker.global_position = Vector3(0, 10, -2)
	check(player.begin_execution(owner, grip, speaker), "Shared-world provider begins an external execution view")
	var observer: Camera3D = player.grab_control.execution_observer
	viewport.own_world_3d = true
	player.grab_control._physics_process(1.0 / 60.0)
	check(not player.is_grabbed() and reasons == ["world_changed"] and player.grab_control.execution_observer == null
		and observer.is_queued_for_deletion() and player.camera.current,
		"Actual World3D switch disposes observer and restores first-person viewport ownership")
	viewport.queue_free()
	await frames()
	# Player removal owns no future camera handoff, but must not leave a transient
	# viewport camera or provider signal behind after the actor exits the tree.
	var removed_player: CharacterBody3D = PLAYER.instantiate()
	world.add_child(removed_player)
	removed_player.set_physics_process(false)
	removed_player.global_position = Vector3(20, .05, 0)
	owner = FramingCaptor.new()
	world.add_child(owner)
	grip = Node3D.new()
	owner.add_child(grip)
	grip.global_position = removed_player.execution_contact_position()
	speaker = Node3D.new()
	owner.add_child(speaker)
	speaker.global_position = Vector3(20, 10, -2)
	check(removed_player.begin_execution(owner, grip, speaker), "Player removal fixture begins third-person capture")
	observer = removed_player.grab_control.execution_observer
	removed_player.queue_free()
	await frames()
	check(not is_instance_valid(observer) and root.get_camera_3d() != observer,
		"Removing the player frees its transient observer without stale viewport ownership")
	owner.queue_free()
	player.camera.make_current()
	await frames()

func test_execution_camera_overhead() -> void:
	var maximum_step := 0.0
	var maximum_pitch := 0.0
	for rate in [30, 60, 120]:
		reset()
		captor.global_position = Vector3(0, 0, -6)
		player.camera.global_basis = Basis.from_euler(Vector3(deg_to_rad(10), deg_to_rad(-20), 0))
		var initial: Transform3D = player.camera.global_transform
		var near_before: float = player.camera.near
		face.global_position = initial.origin + Vector3(0, 8, .2)
		check(capture(), "Overhead camera test obtains actual execution ownership")
		check(player.camera.global_transform.is_equal_approx(initial),
			"Execution preserves the existing first-person position and orientation at capture")
		var previous := initial.basis.get_rotation_quaternion()
		for tick in rate * 2:
			# The speaker passes from just behind the eyes, directly overhead, to
			# just in front. This used to reverse horizontal yaw in one frame.
			var fraction := float(tick) / float(rate * 2 - 1)
			face.global_position = player.camera.global_position + Vector3(0, 8, lerpf(.2, -.2, fraction))
			player.grab_control._process(1.0 / rate)
			var basis: Basis = player.camera.global_basis
			var rotation := basis.get_rotation_quaternion()
			var step := rad_to_deg(previous.angle_to(rotation))
			maximum_step = maxf(maximum_step, step)
			var pitch := rad_to_deg(asin(clampf((-basis.z).y, -1.0, 1.0)))
			maximum_pitch = maxf(maximum_pitch, absf(pitch))
			check(step <= 60.0 / rate + .01, "Execution camera eases in and stays within its slower turn limit at %d Hz" % rate)
			check(absf(basis.x.y) <= .0001 and basis.y.y > 0.0,
				"Execution camera remains upright without roll across the overhead target")
			check(absf(pitch) <= 60.01, "Automatic execution guidance keeps overhead pitch within 60 degrees")
			previous = rotation
		var horizontal_forward: Vector3 = (-player.camera.global_basis.z).slide(Vector3.UP).normalized()
		var initial_horizontal: Vector3 = (-initial.basis.z).slide(Vector3.UP).normalized()
		check(horizontal_forward.dot(initial_horizontal) > .999,
			"Overhead speaker preserves the existing yaw without steering toward the giant's body")
		face.global_position = player.camera.global_position + Vector3(1, 3, -6)
		for tick in rate * 2: player.grab_control._process(1.0 / rate)
		var to_face: Vector3 = (face.global_position - player.camera.global_position).normalized()
		check((-player.camera.global_basis.z).dot(to_face) > .999,
			"Execution camera smoothly converges to the raised speaker after it clears overhead")
		var final_view: Basis = player.camera.global_basis
		player.cancel_execution(captor)
		face.global_position += Vector3(10, 0, 0)
		player.grab_control._process(1.0 / rate)
		check(not player.is_grabbed() and player.grab_control.camera == null
			and is_equal_approx(player.camera.near, near_before),
			"Overhead camera cancellation releases ownership and restores clipping")
		check(player.camera.global_basis.is_equal_approx(final_view),
			"Cancelled execution retains the final upright view without stale speaker tracking")
		check(reasons == ["cancelled"], "Camera crossing produces one ordinary cancellation event")
		captor.global_position = Vector3.ZERO
	# The preview and production share this zero-time contract; capture itself
	# must never turn a view before there has been time to converge.
	var basis := Basis.from_euler(Vector3(.1, .2, 0))
	check(GRAB_CONTROL.execution_view_basis(basis, Vector3.ZERO, Vector3(0, 8, 1), Vector3(0, 0, -6), 0.0).is_equal_approx(basis),
		"Shared execution view helper preserves the initial basis at zero elapsed time")
	print("EXECUTION_CAMERA_METRICS " + JSON.stringify({"rates_hz": [30, 60, 120],
		"maximum_step_degrees": maximum_step, "maximum_pitch_degrees": maximum_pitch,
		"turn_limit_degrees_per_second": 60, "pitch_limit_degrees": 60}))

func test_save_guard() -> void:
	reset()
	check(capture(), "Checkpoint guard begins a real shared execution owner")
	var manager := SaveManagerStub.new()
	manager.name = "PoiInstances"
	world.add_child(manager)
	var generator := SaveGeneratorStub.new()
	generator.name = "WorldGenerator"
	world.add_child(generator)
	var checkpoint := load("res://rv/checkpoint.gd").new() as Node
	world.add_child(checkpoint)
	var storage := NoDiskStorage.new()
	checkpoint.file_operations = storage
	check(not checkpoint.save_world(world, "res://.godot/execution-must-not-save.save"), "Actual checkpoint entry rejects captured player before serialization")
	check(checkpoint.last_error.get("code") == "motion" and checkpoint.last_error.get("field") == "player", "Save rejection comes from the shared grabbed-player guard")
	check(storage.writes == 0, "Rejected execution never invokes checkpoint storage")
	player.cancel_execution(captor)
	checkpoint.queue_free()
	manager.queue_free()
	generator.queue_free()
	await frames()

func test_blocked_lift() -> void:
	reset()
	var ceiling := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, .3, 8)
	collision.shape = box
	ceiling.add_child(collision)
	world.add_child(ceiling)
	ceiling.position = Vector3(0, 3, 0)
	await frames()
	check(capture(), "Capture below ceiling starts at real contact")
	anchor.global_position += Vector3.UP * 10.0
	player._physics_process(1.0 / 60.0)
	check(not player.is_grabbed() and not player.is_player_dead, "Blocked capsule sweep releases player alive")
	check(player.global_position.y < 1.5, "Swept lift never teleports through the ceiling")
	check(reasons == ["execution_path_blocked"], "Blocked path reports precise cancellation reason")
	ceiling.queue_free()
	await frames()

func test_occupied_seat_extraction() -> void:
	reset()
	var seat := load("res://equipment/driver_seat.tscn").instantiate() as RigidBody3D
	world.add_child(seat)
	seat.freeze = true
	seat.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	seat.collision_layer = 1
	seat.collision_mask = 0
	seat.global_position = Vector3(40, .05, 0)
	await frames()
	player.global_position = seat.global_position
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player.body_collision_shape.shape
	query.transform = player.global_transform * player.body_collision_shape.transform
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	var hits := player.get_world_3d().direct_space_state.intersect_shape(query)
	check(hits.any(func(hit: Dictionary): return hit.collider == seat),
		"Production seat back/cushion genuinely overlaps the survivor's full body shape")
	check(seat.get_node("CollisionShape3D").get_parent() == seat,
		"Production seat back belongs to the occupied seat body, rather than the RV shell")
	check(not capture(), "Unoccupied seat remains solid to a ground execution capture")
	check(player.enter_seat_mode(seat), "Extraction fixture enters the actual driver-seat mode")
	seat.current_driver = player
	var before: Vector3 = player.global_position
	var seat_rid := seat.get_rid()
	check(capture(), "Occupied seat overlap permits giant execution without avoiding its back")
	player.set_physics_process(false)
	check(player.grab_control.execution_seat == seat and player.grab_control.execution_seat_rid == seat_rid,
		"Execution retains only the occupied seat identity captured before driver release")
	check(player.seated_in == null and seat.current_driver == null,
		"Seat extraction still transfers both seat owners to the giant")
	anchor.global_position += Vector3.UP * 4.0
	player._physics_process(1.0 / 60.0)
	check(player.is_executing() and player.global_position.is_equal_approx(before + Vector3.UP * 4.0),
		"Swept execution lift ignores the occupied seat's back and cushion")
	player.cancel_execution(captor)
	check(player.grab_control.execution_seat == null and not player.grab_control.execution_seat_rid.is_valid(),
		"Cancellation clears the transient occupied-seat exclusion")
	check(seat.collision_layer == 1 and not player.get_collision_exceptions().has(seat),
		"Execution seat exclusion does not alter ordinary collision layers or body exceptions")
	reset()
	player.global_position = seat.global_position
	check(not capture(), "A later ground capture cannot retain the former occupied-seat exemption")
	check(player.enter_seat_mode(seat), "Wall-blocked extraction enters the actual seat")
	seat.current_driver = player
	var wall := StaticBody3D.new()
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(3, .3, 3)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	world.add_child(wall)
	wall.global_position = seat.global_position + Vector3.UP * 3.0
	await frames()
	before = player.global_position
	check(capture(), "Occupied seat can begin extraction below an independent solid wall")
	player.set_physics_process(false)
	anchor.global_position += Vector3.UP * 8.0
	player._physics_process(1.0 / 60.0)
	check(not player.is_grabbed() and player.global_position.y < before.y + 1.5,
		"Occupied-seat exclusion still collision-sweeps the full body against independent shell/world geometry")
	check(reasons == ["execution_path_blocked"] and not player.grab_control.execution_seat_rid.is_valid()
		and player.grab_control.execution_seat == null,
		"Wall-blocked extraction clears both seat identity and execution ownership")
	wall.queue_free()
	await frames()
	reset()
	check(player.enter_seat_mode(seat), "Removed-seat cleanup enters the actual seat")
	seat.current_driver = player
	check(capture(), "Removed-seat cleanup begins occupied-seat execution")
	player.set_physics_process(false)
	seat.queue_free()
	await frames()
	player._physics_process(1.0 / 60.0)
	check(player.is_executing() and player.grab_control.execution_seat == null
		and not player.grab_control.execution_seat_rid.is_valid(),
		"Removing the released seat clears its stale RID without cancelling the giant's valid ownership")
	player.cancel_execution(captor)

func test_mode_cleanup() -> void:
	reset()
	var ladder: RVLadder = load("res://equipment/side_door_ladder.tscn").instantiate()
	world.add_child(ladder)
	ladder.freeze = true
	ladder.position.x = 10.0
	await frames()
	# Real ladder ownership fields/exceptions are the same ones installed by
	# begin_ladder_climb; contact eligibility belongs to the giant controller.
	player.locomotion_state = player.LocomotionState.CLIMBING
	player.active_climb_ladder = ladder
	player.active_climb_rv = ladder
	player.add_collision_exception_with(ladder)
	ladder.availability_changed.connect(player._validate_active_ladder)
	ladder.tree_exiting.connect(player._active_ladder_removed)
	check(capture(), "Giant can capture climbing player")
	check(player.active_climb_ladder == null and player.active_climb_rv == null and player.locomotion_state == player.LocomotionState.NORMAL, "Capture releases ladder state and carrier")
	check(not player.get_collision_exceptions().has(ladder), "Ladder collision exception is removed")
	player.cancel_execution(captor)
	ladder.queue_free()
	reset()
	var rv: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(rv)
	rv.position = Vector3(20, 0, 0)
	rv.get_node("Chassis").freeze = true
	await frames()
	var seat: Node3D
	for child in rv.find_children("*", "Node3D", true, false):
		if child.has_method("release_for_execution"):
			seat = child
			break
	check(seat != null, "Production RV has execution-aware driver seat")
	if seat != null:
		check(player.enter_seat_mode(seat), "Driver enters normal seat mode")
		seat.current_driver = player
		seat.seat_camera.make_current()
		rv.get_node("Chassis").set_driving_state(true)
		var before: Vector3 = player.global_position
		var overlapping_roof := StaticBody3D.new()
		var roof_collision := CollisionShape3D.new()
		var roof_shape := BoxShape3D.new()
		roof_shape.size = Vector3(3, .3, 3)
		roof_collision.shape = roof_shape
		overlapping_roof.add_child(roof_collision)
		world.add_child(overlapping_roof)
		overlapping_roof.global_position = before + Vector3.UP * 1.15
		await frames()
		check(not capture(), "Disabled seated capsule overlapping intact roof cannot bypass a sweep")
		check(player.seated_in == seat and seat.current_driver == player and not player.is_grabbed(), "Rejected overlapping source preserves driver ownership")
		overlapping_roof.queue_free()
		await frames()
		var seated_view_before: Basis = seat.seat_camera.global_basis
		check(capture(), "Exposed driver transfers ownership to execution")
		check(player.camera.global_basis.is_equal_approx(seated_view_before),
			"Seat extraction preserves the driver's actual view before converging toward the speaker")
		check(player.global_position.is_equal_approx(before), "Seat extraction starts without forced-exit teleport")
		check(player.seated_in == null and seat.current_driver == null and player.camera.current and not player.body_collision_shape.disabled, "Capture clears both seat owners and restores full-body collider/view")
		player.cancel_execution(captor)
	# A moving roof carrier must not add its velocity/transform to the lift.
	reset()
	var chassis: Node3D = rv.get_node("Chassis")
	player.rv_support.rv = chassis
	player.rv_support.surface = chassis.get_node("RoofFront")
	player.rv_support.previous = chassis.global_transform
	player.rv_support.carrier_velocity = Vector3(12, 0, -20)
	player.released_carrier_velocity = Vector3(4, 0, -8)
	player.velocity = Vector3(1, 2, 3)
	check(capture(), "Roof-supported player's shared owner can transfer")
	check(player.rv_support.rv == null and player.rv_support.surface == null and player.rv_support.carrier_velocity == Vector3.ZERO, "Capture clears moving RV support ownership and velocity")
	check(player.released_carrier_velocity == Vector3.ZERO and player.velocity == Vector3.ZERO, "Capture removes inherited carrier motion from the execution path")
	player.cancel_execution(captor)
	rv.queue_free()
	await frames()

func test_crush_and_respawn() -> void:
	reset()
	check(player.add_item("Scrap", false, "res://props/scrap.tscn", {"condition": 37.0}), "Crush inventory uses damaged real Item state")
	var inventory_before: Array = player.inventory.items.duplicate(true)
	var slot_before: int = player.inventory.active_slot
	player.sever_part(&"left_arm")
	player.sever_part(&"left_leg")
	await frames()
	var effects_before := get_nodes_in_group("player_detached_parts").size()
	var changes_before := body_events
	check(player.is_crawling() and capture(), "Giant supports already-dismembered crawling target")
	# Production keeps player physics enabled through death. Earlier cases
	# disable automatic ticks only so their explicit swept steps are repeatable.
	player.set_physics_process(true)
	check(player.complete_execution(captor), "Execution completes once")
	check(not player.complete_execution(captor), "Repeated crush cannot replay death/cuts")
	check(player.is_player_dead and player.current_player_health == 0.0 and not player.is_grabbed(), "Crush releases ownership and enters ordinary death")
	for part: StringName in PlayerBodyState.PARTS:
		check(not player.body_state.has_part(part), "Crush separates surviving part " + String(part))
	check(get_nodes_in_group("player_detached_parts").size() == effects_before + 3, "Missing parts are not detached twice")
	check(body_events == changes_before + 1, "Batch crush applies body capabilities once")
	check(reasons == ["death"], "Crush and duplicate completion emit exactly one death release")
	check(player.inventory.items == inventory_before and player.inventory.active_slot == slot_before, "Fatal crush preserves Item identity, condition and backpack slot")
	await frames()
	check(player.ragdoll_control.active, "Execution uses existing live ragdoll")
	var detached_head: Node3D = player.ragdoll_control.detached_head
	check(player.ragdoll_control.following_detached_head and is_instance_valid(detached_head), "Death camera follows the actual separated head")
	check((player.camera.cull_mask & PlayerModelVisual.FULL_BODY_LAYER) == 0, "First-person camera excludes its separated head layer")
	if is_instance_valid(detached_head):
		for mesh: MeshInstance3D in detached_head.meshes:
			check(mesh.layers == PlayerModelVisual.FULL_BODY_LAYER, "Separated head remains observer-visible but excluded from local death camera")
	check(not player.get_node("Visuals").local_body.visible, "Local torso stays hidden during stable-view ragdoll death")
	var corpses_before := world.find_children("*", "Node3D", true, false).filter(func(node): return node is CorpseProp and node.kind == "player").size()
	player._respawn()
	check(not player.is_player_dead and player.can_drive() and player.camera.current, "Existing respawn restores all parts and input")
	check(player.body_state.has_part(&"head") and player.usable_arms() == 2, "Respawn restores head and both arms")
	check(not player.ragdoll_control.following_detached_head and player.get_node("Visuals").local_body.visible, "Revival restores local torso and clears separated-head camera ownership")
	if is_instance_valid(detached_head):
		for mesh: MeshInstance3D in detached_head.meshes:
			check(mesh.layers == 1, "Old separated head returns to ordinary world visibility after revival")
	check(player.inventory.items == inventory_before and player.inventory.active_slot == slot_before and is_instance_valid(player.held_item_node), "Revival retains saved inventory and restores held preview")
	check(player.is_physics_processing() and player.is_processing_unhandled_input() and not player.is_grabbed(), "Revival restores physics and ordinary input without stale ownership")
	var corpses := world.find_children("*", "Node3D", true, false).filter(func(node): return node is CorpseProp and node.kind == "player")
	check(corpses.size() == corpses_before + 1, "Real ragdoll revival leaves one persistent player corpse")
	if not corpses.is_empty():
		for part: StringName in PlayerBodyState.PARTS:
			check(not corpses.back().body_state.has_part(part), "Player corpse preserves execution cut state for " + String(part))

func test_world_and_anchor_cleanup() -> void:
	reset()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16, 16)
	world.add_child(viewport)
	var owner := Node3D.new()
	viewport.add_child(owner)
	var owner_anchor := Node3D.new()
	owner.add_child(owner_anchor)
	owner_anchor.global_position = player.execution_contact_position()
	var owner_face := Node3D.new()
	owner.add_child(owner_face)
	owner_face.global_position = Vector3(0, 13, -2)
	check(player.begin_execution(owner, owner_anchor, owner_face), "Shared World3D owner can begin execution")
	viewport.own_world_3d = true
	player.grab_control._physics_process(1.0 / 60.0)
	check(not player.is_grabbed() and reasons == ["world_changed"] and player.grab_control.camera == null, "Actual World3D switch clears control and camera without requiring world-transition helper")
	player.grab_control.immunity = 0.0
	check(not player.begin_execution(owner, owner_anchor, owner_face), "Cross-world owner cannot capture player")
	viewport.queue_free()
	await frames()
	reset()
	check(capture(), "Anchor removal cleanup setup")
	anchor.queue_free()
	await frames()
	player._physics_process(1.0 / 60.0)
	check(not player.is_grabbed() and reasons == ["execution_anchor_removed"] and player.grab_control.camera == null, "Removed grip anchor releases execution without leaving camera ownership")
	anchor = Node3D.new()
	captor.add_child(anchor)

func test_owner_and_world_cleanup() -> void:
	reset()
	check(capture(), "World transition cleanup setup")
	player.complete_world_transition(Transform3D(Basis.IDENTITY, Vector3(12, .05, 0)))
	check(not player.is_grabbed() and player.grab_control.camera == null and reasons == ["world_transition"], "World transition removes execution and camera state")
	reset()
	check(capture(), "Owner removal cleanup setup")
	captor.queue_free()
	await frames()
	check(not player.is_grabbed() and player.grab_control.camera == null and reasons.has("owner_removed"), "Removing giant safely releases player and broadcasts audio cleanup")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.body_state_changed.connect(func(): body_events += 1)
	player.grab_control.released.connect(func(reason: String): reasons.append(reason))
	captor = Node3D.new()
	world.add_child(captor)
	anchor = Node3D.new()
	captor.add_child(anchor)
	face = Node3D.new()
	captor.add_child(face)
	await frames()
	test_ownership_lift_cancel()
	test_execution_camera_overhead()
	await test_execution_framing_cleanup()
	await test_third_person_world_and_player_removal()
	await test_save_guard()
	await test_blocked_lift()
	await test_occupied_seat_extraction()
	await test_mode_cleanup()
	await test_crush_and_respawn()
	await frames()
	await test_world_and_anchor_cleanup()
	await test_owner_and_world_cleanup()
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: execution ownership, swept lift, first/third-person camera lifecycle and obstacle clipping, input/held-item inventory, isolated no-disk save rejection, climbing/driver/RV-support transfer, missing-limb single death, persistent corpse/revival, actual World3D/anchor/owner cleanup and cancellation")
	quit(0 if failures.is_empty() else 1)
