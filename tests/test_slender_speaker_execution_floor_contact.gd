extends "res://tests/test_slender_speaker_execution.gd"
## Real production capsule/Jolt resting contacts; all solids share one body,
## as the RV deck and other chassis collision shapes do.
var floor_body: StaticBody3D
class LiftRV extends RigidBody3D:
	func add_item(_item: Node) -> void: pass
	func deduct_materials(_materials: Dictionary) -> bool: return true
var lift_rv: LiftRV
var lift_giant: SlenderSpeaker

func lift_wall(kind: String, x := -.515) -> CollisionObject3D:
	var body: CollisionObject3D
	if kind == "item":
		var item := Item.new()
		item.freeze = true
		item.is_being_placed = true
		body = item
	else:
		var panel := RVStructurePanel.new()
		panel.structure_kind = "side"
		body = panel
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.2, 1.98, 3)
	collision.shape = shape
	body.add_child(collision)
	lift_rv.add_child(body)
	body.collision_layer = 1
	body.position = Vector3(x, 1.5, 0)
	body.rotation.z = -.08
	if kind == "roof": body.structure_kind = "roof"
	return body

func test_swept_lift_wall_clearance() -> void:
	var original_captor := captor
	lift_rv = LiftRV.new()
	lift_rv.freeze = true
	world.add_child(lift_rv)
	lift_rv.add_to_group(Groups.RV)
	lift_giant = load("res://enemies/slender_speaker/slender_speaker.tscn").instantiate()
	lift_giant.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(lift_giant)
	lift_giant.global_position = Vector3(100, 0, 0)
	lift_giant.phase = SlenderSpeaker.Phase.LIFT
	lift_giant.target_vehicle = lift_rv
	captor = lift_giant
	for kind in ["side", "excessive", "item", "roof", "ordinary_owner", "spent_budget"]:
		reset()
		captor = original_captor if kind == "ordinary_owner" else lift_giant
		var wall := lift_wall("side" if kind in ["excessive", "ordinary_owner"] else kind)
		await frames()
		check(player.grab_control._execution_volume_clear(captor), kind + " lift obstruction starts outside the complete player volume")
		check(capture(), kind + " lift obstruction permits initial ownership before the actual swept hit")
		if kind == "spent_budget": player.grab_control.execution_wall_clearance_distance = .05
		var before := player.global_position
		var rise := .8 if kind == "excessive" else .35
		anchor.global_position += Vector3.UP * rise
		player.grab_control.advance_execution(1.0 / 60.0)
		print("LIFT_CLEARANCE_RESULT ", kind, " position=", player.global_position, " executing=", player.is_executing(), " spent=", player.grab_control.execution_wall_clearance_distance, " reasons=", reasons)
		if kind == "side":
			check(player.is_executing() and player.global_position.y > before.y + rise - .01
				and player.global_position.x > before.x and player.global_position.x - before.x <= .05
				and player.grab_control._execution_volume_clear(captor),
				"Rolled side-wall lift uses only a bounded swept inward clearance and preserves every solid")
			check(player.grab_control.execution_wall_clearance_distance > 0.0
				and player.grab_control.execution_wall_clearance_distance <= .05,
				"Side-wall correction records a cumulative five-centimetre maximum")
		else:
			check(not player.is_executing() and reasons == ["execution_path_blocked"],
				kind + " obstruction still cancels the swept lift")
			check(is_equal_approx(player.global_position.x, before.x), kind + " rejection cannot move the player laterally through the obstruction")
			if kind == "item": check(not wall.is_destroyed and is_equal_approx(wall.current_health, 100.0), "Lift clearance preserves Item blockers and their health")
		wall.queue_free()
		await frames()
	captor = original_captor
	if player.is_grabbed(): player.grab_control.end("fixture_reset")
	lift_giant.queue_free()
	lift_rv.queue_free()
	await frames()

func add_box(size: Vector3, location: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	floor_body.add_child(collision)
	collision.position = location
	return collision

func test_shallow_floor() -> void:
	reset()
	player.global_position.y = -.253
	check(not player.grab_control._execution_volume_clear(captor), "Fixture starts with a real 3mm capsule/deck overlap")
	var before := player.global_position
	check(capture(), "Shallow floor overlap recovers and begins execution")
	var recovered := player.global_position
	check(recovered.y > before.y and recovered.y - before.y <= .0061
		and recovered.x == before.x and recovered.z == before.z,
		"Floor recovery has a bounded vertical lift without lateral displacement")
	check(player.grab_control._execution_volume_clear(captor), "Recovery leaves the complete capsule outside every solid")
	anchor.global_position += Vector3.UP * 2.0
	player.grab_control.advance_execution(1.0 / 60.0)
	check(player.is_executing() and player.global_position.is_equal_approx(recovered + Vector3.UP * 2.0),
		"Recovered starting contact follows the actual swept lift")
	print("EXECUTION_FLOOR_RECOVERY lift_m=", recovered.y - before.y)

func test_blocked_recovery() -> void:
	reset()
	player.global_position.y = -.270
	var before := player.global_position
	check(not capture() and player.global_position == before and not player.is_grabbed(),
		"Deep floor overlap rejects capture without changing position or ownership")
	for kind in ["wall", "roof", "sweep_roof"]:
		reset()
		player.global_position.y = -.253
		var solid: CollisionShape3D
		if kind == "wall":
			solid = add_box(Vector3(.05, 3, 3), Vector3(.414, 1, 0))
		elif kind == "roof":
			solid = add_box(Vector3(3, .05, 3), Vector3(0, 1.521, 0))
		else:
			# Lower roof face is initially 2mm above the capsule. The 4mm
			# recovery must sweep into it rather than skipping over it.
			solid = add_box(Vector3(3, .0005, 3), Vector3(0, 1.49925, 0))
		await frames()
		before = player.global_position
		check(not capture() and player.global_position == before and not player.is_grabbed(),
			"Shallow floor contact cannot bypass a same-body %s" % kind)
		solid.queue_free()
		await frames()

func test_shallow_wall_contact() -> void:
	reset()
	player.global_position.y = -.253
	var wall := add_box(Vector3(.05, 3, 3), Vector3(.424, 1, 0))
	await frames()
	var before := player.global_position
	check(capture(), "Simultaneous shallow deck and side-wall resting contacts recover")
	var recovered := player.global_position
	check(recovered.x < before.x and recovered.y > before.y
		and recovered.distance_to(before) <= .0061
		and player.grab_control._execution_volume_clear(captor),
		"Normal-directed recovery clears both contacts within one total 6mm bound")
	# The permitted starting contact cannot authorize even a small later move
	# back through the intact same-body wall.
	anchor.global_position += Vector3.RIGHT * .02
	player.grab_control.advance_execution(1.0 / 60.0)
	check(not player.is_executing() and reasons == ["execution_path_blocked"]
		and player.global_position.x < before.x,
		"A later full-body sweep into the recovered wall still cancels")
	wall.queue_free()
	await frames()

func test_advance_floor_contact() -> void:
	reset()
	player.global_position.y = -.249
	check(capture(), "Advance fixture begins from a clear full body volume")
	var before := player.global_position
	# A moving vehicle deck can establish a new shallow resting contact.
	floor_body.position.y = .004
	await frames()
	check(not player.grab_control._execution_volume_clear(captor), "Moving floor creates real contact during execution")
	player.grab_control.advance_execution(1.0 / 60.0)
	check(player.is_executing() and player.global_position.y > before.y
		and player.global_position.y - before.y <= .0061,
		"Execution advance recovers only a new shallow floor contact")
	var recovered := player.global_position
	player.grab_control.advance_execution(1.0 / 60.0)
	check(player.is_executing() and player.global_position == recovered,
		"Recovery adjusts the grip offset instead of dragging the player back into the deck")
	floor_body.position.y += .020
	await frames()
	player.grab_control.advance_execution(1.0 / 60.0)
	check(not player.is_executing() and reasons == ["execution_path_blocked"] and player.global_position == recovered,
		"A deep overlap during advance cancels without further extraction")
	floor_body.position.y = 0
	await frames()

func test_world_scale_floor_contact() -> void:
	reset()
	# At the live cabin's world height Jolt reports a real deck overlap with
	# contact points only one float ULP apart. Their subtraction cannot supply
	# a reliable normal; this previously released ownership at lift +0.08s.
	floor_body.position = Vector3(0, 1.74005, -24.08685)
	player.global_position = Vector3(-1.396189, 1.4900498, -24.08685)
	await frames()
	check(not player.grab_control._execution_volume_clear(captor),
		"World-scale fixture contains the real micrometre capsule/deck overlap")
	var before := player.global_position
	check(capture(), "Micrometre world-scale floor contact obtains execution ownership")
	check(player.global_position.y > before.y and player.global_position.y - before.y <= .0011
		and player.grab_control._execution_volume_clear(captor),
		"World-scale floor recovery remains bounded and clears the complete capsule")
	anchor.global_position += Vector3.UP * 2.0
	player.grab_control.advance_execution(1.0 / 60.0)
	check(player.is_executing() and player.global_position.y > before.y + 1.99,
		"World-scale resting contact survives the actual upward execution sweep")
	player.cancel_execution(captor, "fixture_reset")
	floor_body.position = Vector3.ZERO
	await frames()

func test_resting_player() -> void:
	reset()
	player.global_position.y = .2
	player.set_physics_process(true)
	await frames(90)
	player.set_physics_process(false)
	check(player.is_on_floor(), "Production player has settled with normal floor physics")
	var before := player.global_position
	check(capture(), "A naturally resting production player can begin execution")
	anchor.global_position += Vector3.UP * 2.0
	player.grab_control.advance_execution(1.0 / 60.0)
	check(player.is_executing() and player.global_position.y > before.y + 1.99,
		"Normal floor physics does not prevent the swept execution lift")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	floor_body = StaticBody3D.new()
	world.add_child(floor_body)
	add_box(Vector3(10, .2, 10), Vector3(0, -.1, 0))
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.grab_control.released.connect(func(reason: String): reasons.append(reason))
	captor = Node3D.new()
	world.add_child(captor)
	anchor = Node3D.new()
	captor.add_child(anchor)
	face = Node3D.new()
	captor.add_child(face)
	await frames()
	test_shallow_floor()
	await test_blocked_recovery()
	await test_shallow_wall_contact()
	await test_advance_floor_contact()
	await test_world_scale_floor_contact()
	await test_resting_player()
	await test_swept_lift_wall_clearance()
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: bounded resting-contact recovery at capture and advance, world-scale precision, shallow wall/deck recovery, later wall/roof/swept roof blocking, deep overlap refusal and naturally resting production player lift")
	quit(0 if failures.is_empty() else 1)
