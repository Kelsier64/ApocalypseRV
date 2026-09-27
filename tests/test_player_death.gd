extends SceneTree
const PLAYER = preload("res://player/player.tscn")
var failures: Array[String] = []
var actor: CharacterBody3D
var arena: Node3D
var measures: Array = []

func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value and note not in failures: failures.append(note)
func steps(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func duration_ticks(original_120hz_count: int) -> int:
	return ceili(original_120hz_count * Engine.physics_ticks_per_second / 120.0)

func duration_steps(original_120hz_count: int) -> void:
	await steps(duration_ticks(original_120hz_count))

func floor_box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	arena.add_child(body)
	body.position = at
	return body

func die_and_recover(label: String, expected_x := NAN) -> void:
	var view: Basis = actor.camera.global_basis
	var start_height: float = actor.camera.global_position.y
	actor.damage_cooldown = 0
	actor.take_damage(1000)
	actor._player_die() # Duplicate lethal calls must not restart or stack timers.
	check(actor.is_player_dead and actor.get_player_mode() == actor.PlayerMode.DEAD, label + " locks gameplay immediately")
	await steps(2)
	var control: Node = actor.ragdoll_control
	if is_finite(expected_x):
		check(absf(actor.death_velocity.x - expected_x) < .001 and absf(control.bodies["pelvis"].linear_velocity.x - expected_x) < .2, label + " released platform velocity reaches the physical body once")
	check(control.active and control.bodies.size() == 14 and actor.body_collision_shape.disabled, label + " physics replaces capsule")
	check(not actor.get_node("Visuals").local_body.visible and actor.get_node("Visuals").death_shadows.size() == 5, label + " local tumbling torso is culled but shadows remain")
	check(actor.seated_in == null and not actor.in_ui_mode and not actor.is_grabbed(), label + " releases prior mode")
	check(not actor.enter_ui_mode(), label + " dead actor cannot enter UI")
	var anchor := actor.global_position
	var minimum_height := start_height
	var peak_gap := 0.0
	var peak_joint := ""
	var peak_frame := 0
	var peak_speed := 0.0
	Input.action_press("move_forward")
	for frame in duration_ticks(180):
		await steps(1)
		check(actor.global_position.distance_to(anchor) < .0001, label + " movement cannot compete with physics")
		check(actor.camera.global_basis.is_equal_approx(view), label + " death view does not roll or turn")
		minimum_height = minf(minimum_height, actor.camera.global_position.y)
		for body: PhysicalBone3D in control.bodies.values():
			check(body.global_transform.is_finite() and body.global_basis.get_scale().distance_to(Vector3.ONE) < .0002, label + " finite unscaled physical bones")
			peak_speed = maxf(peak_speed, body.linear_velocity.length())
		for link: Dictionary in control.links:
			var gap: float = (link.parent.global_transform * link.parent_frame).origin.distance_to((link.child.global_transform * link.child.joint_offset).origin)
			if gap > peak_gap:
				peak_joint = link.child.get("bone_name")
				peak_frame = frame
			peak_gap = maxf(peak_gap, gap)
	Input.action_release("move_forward")
	check(peak_gap < .025 and peak_speed < 12.0, label + " no disconnected joints or explosive velocity")
	check(start_height - minimum_height > .4, label + " first person follows the falling head")
	await duration_steps(90)
	check(not actor.is_player_dead and not control.active and not actor.body_collision_shape.disabled, label + " two-second respawn restores capsule")
	check(actor.current_player_health == actor.max_player_health and actor.current_stamina == actor.MAX_STAMINA, label + " health and stamina restored")
	check(not control.simulator.is_simulating_physics() and not control.simulator.active, label + " physics stops on recovery")
	for body: PhysicalBone3D in control.bodies.values():
		check(body.collision_layer == 0 and body.collision_mask == 0, label + " inactive bones cannot block gameplay")
	check(actor.camera.position.distance_to(Vector3(0, 1.78, -.2)) < .0001, label + " first-person camera returns to its anchor")
	check(actor.get_node("Visuals").local_body.visible, label + " local body returns on respawn")
	var start := actor.global_position
	Input.action_press("move_back")
	await duration_steps(60)
	Input.action_release("move_back")
	check(actor.global_position.distance_to(start) > 1.0, label + " movement works after respawn")
	measures.append({"case": label, "camera_drop_m": start_height - minimum_height, "max_joint_gap_m": peak_gap, "peak_joint": peak_joint, "peak_frame": peak_frame, "max_speed_m_s": peak_speed, "recovery_move_m": actor.global_position.distance_to(start)})

func run() -> void:
	check(Engine.physics_ticks_per_second == ProjectSettings.get_setting("physics/common/physics_ticks_per_second"), "Production physics uses the configured rate")
	print("PLAYER_DEATH_PHYSICS_HZ ", Engine.physics_ticks_per_second)
	arena = Node3D.new()
	root.add_child(arena)
	floor_box(Vector3(0, -.2, 0), Vector3(60, .4, 60))
	actor = PLAYER.instantiate()
	arena.add_child(actor)
	actor.position = Vector3(0, .2, 0)
	await duration_steps(90)
	check(actor.ragdoll_control.simulator == null, "Physical bodies are lazy and absent before first death")
	actor.add_item("Scrap", false, "res://props/scrap.tscn")
	actor.enter_ui_mode()
	await die_and_recover("standing_from_ui")
	check(actor.held_item_node.visible and actor.inventory.items.size() == 1, "Held item and inventory survive death")
	if DisplayServer.get_name() != "headless":
		var yaw_before := actor.rotation.y
		var pitch_before: float = actor.camera.rotation.x
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(90, 25)
		motion.position = root.get_visible_rect().size * .5
		Input.parse_input_event(motion)
		await steps(4)
		check(absf(actor.rotation.y - yaw_before) > .1 and absf(actor.camera.rotation.x - pitch_before) > .02, "Real mouse input turns yaw and pitch after respawn")
		print("RESPAWN_MOUSE yaw=", actor.rotation.y - yaw_before, " pitch=", actor.camera.rotation.x - pitch_before)
		actor.rotation = Vector3.ZERO
		actor.camera.rotation = Vector3.ZERO
	actor.position = Vector3(0, 1.8, 0)
	actor.velocity = Vector3(1.0, -1.0, 0)
	await die_and_recover("airborne")
	actor.position = Vector3(0, 1.8, 0)
	actor.velocity = Vector3(1.0, -1.0, 0)
	actor.released_carrier_velocity = Vector3(2.0, 0, 0)
	await die_and_recover("airborne_carrier", 3.0)
	# Another World3D must not leave physical bones registered in the old world.
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var original_arena := arena
	arena = Node3D.new()
	viewport.add_child(arena)
	floor_box(Vector3(0, -.2, 0), Vector3(60, .4, 60))
	actor.reparent(arena)
	actor.complete_world_transition(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	await duration_steps(90)
	await die_and_recover("independent_world")
	# A covered body must remain dead until a real standing volume is available.
	actor.position = Vector3(0, 0, 0)
	actor.damage_cooldown = 0
	actor.take_damage(1000)
	await duration_steps(160)
	var lid := floor_box(Vector3(0, 1.45, 0), Vector3(20, .15, 20))
	# Ray candidates begin below this lid, so its top cannot become a fake exit.
	await duration_steps(110)
	check(actor.is_player_dead and actor.ragdoll_control.active, "No forced respawn through blocked standing volume")
	lid.queue_free()
	await duration_steps(90)
	check(not actor.is_player_dead, "Clearing obstruction permits retry and recovery")
	actor.damage_cooldown = 0
	actor.take_damage(1000)
	await duration_steps(30)
	actor.reparent(original_arena)
	actor.complete_world_transition(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	viewport.queue_free()
	arena = original_arena
	await duration_steps(30)
	check(actor.ragdoll_control.active and actor.get_world_3d() == arena.get_world_3d(), "Cancelled transition rebinds a dead actor to its destination world")
	check(actor.ragdoll_control.bodies["pelvis"].global_position.distance_to(actor.global_position) < 2.0, "Old-space physical pose is not retained after return")
	await duration_steps(270)
	check(not actor.is_player_dead, "Death during a world transfer can still recover")
	var vehicle: Node3D = load("res://rv/new_rv.tscn").instantiate()
	arena.add_child(vehicle)
	var chassis: VehicleBody3D = vehicle.get_node("Chassis")
	chassis.freeze = true
	chassis.position = Vector3(8, 1, 0)
	await steps(10)
	actor.complete_world_transition(Transform3D(Basis.IDENTITY, chassis.to_global(Vector3(0, 3, 0))))
	await duration_steps(120)
	var carried_start := actor.global_position
	for frame in duration_ticks(120):
		chassis.position.x += 3.0 / Engine.physics_ticks_per_second
		await steps(1)
	check(actor.global_position.x - carried_start.x > 2.8, "Real RV roof support carries the standing player")
	actor.damage_cooldown = 0
	actor.take_damage(1000)
	await steps(2)
	var pelvis_speed: Vector3 = actor.ragdoll_control.bodies["pelvis"].linear_velocity
	check(pelvis_speed.x > 2.5 and pelvis_speed.x < 3.5, "Death inherits the measured 3 m/s carrier motion once")
	for frame in duration_ticks(300):
		chassis.position.x += 3.0 / Engine.physics_ticks_per_second
		await steps(1)
	check(not actor.is_player_dead, "Death from a moving RV roof can recover on supported ground")
	var seat: Node = chassis.get_node("DriverSeat")
	seat.interact_hold(actor)
	check(actor.seated_in == seat, "Real driver seat fixture entered")
	seat.seat_camera.rotation = Vector3(-.15, .4, 0)
	var seat_view: Basis = seat.seat_camera.global_basis
	# Seat exit chooses a clear position; the camera contract starts there.
	actor.damage_cooldown = 0
	actor.take_damage(1000)
	await steps(3)
	check(actor.seated_in == null and seat.current_driver == null and actor.visible and actor.ragdoll_control.active, "Seated death releases driver and reveals physical body")
	check(actor.camera.global_basis.is_equal_approx(seat_view), "Driver death keeps the seat camera's final viewing direction")
	await duration_steps(300)
	check(not actor.is_player_dead and actor.is_processing_unhandled_input(), "Seated death restores ground input")
	print("PLAYER_DEATH_METRICS ", JSON.stringify(measures))
	arena.queue_free()
	await steps(3)
	if failures.is_empty(): print("PASS: production player death, fixed first-person view, collision-safe recovery, seat and World3D lifecycle")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
