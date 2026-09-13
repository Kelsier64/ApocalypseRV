extends SceneTree

var failures: Array[String] = []
var world: Node3D
var rv: Node3D
var player: CharacterBody3D
var monster: CharacterBody3D

func _init() -> void:
	_run.call_deferred()

func _tick() -> void:
	await physics_frame
	await process_frame

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var vehicle: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(vehicle)
	rv = vehicle.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	rv.position.y = 1.2
	player = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(2.65, 1.0, 0)
	player.rotation.y = PI / 2.0
	await _tick()
	Input.action_press("move_forward")
	var climbed := false
	var reached_roof := false
	for i in range(240):
		if climbed:
			rv.position.z -= 0.08
			rv.rotate_y(0.003)
		await _tick()
		player._physics_process(1.0 / 60.0)
		climbed = climbed or player.locomotion_state == player.LocomotionState.CLIMBING
		if climbed and player.locomotion_state == player.LocomotionState.NORMAL:
			var local: Vector3 = rv.to_local(player.global_position)
			reached_roof = local.y > 2.1 and local.x < 2.0
			print("Player top-out: ", player.position)
			break
	Input.action_release("move_forward")
	_expect(climbed, "Player enters climbing against actual RV wall.")
	_expect(reached_roof, "Player reaches the actual RV roof with collisions enabled.")
	_expect(not player.body_collision_shape.disabled, "Player capsule remains active after top-out.")
	for i in range(5):
		await _tick()
		player._physics_process(1.0 / 60.0)
	var roof_anchor: Vector3 = rv.to_local(player.global_position)
	for i in range(60):
		rv.position.z -= 0.12
		rv.rotate_y(0.005)
		await _tick()
		player._physics_process(1.0 / 60.0)
	_expect(rv.to_local(player.global_position).distance_to(roof_anchor) < 0.12, "Idle player stays on the roof through driving and steering.")
	# Exercise actual VehicleBody integration as well as scripted transforms.
	rv.freeze = false
	rv.gravity_scale = 0.0
	rv.linear_velocity = Vector3(0, 0, -6)
	rv.angular_velocity = Vector3(0, 0.12, 0)
	roof_anchor = rv.to_local(player.global_position)
	for i in range(60):
		await _tick()
		player._physics_process(1.0 / 60.0)
	_expect(rv.to_local(player.global_position).distance_to(roof_anchor) < 0.2, "Player also follows a physics-driven VehicleBody without double platform motion.")
	rv.freeze = true
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	rv.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))

	# Verify both actor controllers carry a point through translation AND turning.
	monster = load("res://enemies/zombie.tscn").instantiate()
	world.add_child(monster)
	monster.set_physics_process(false)
	player.position = Vector3(0, 3.7, 0)
	monster.position = Vector3(2.65, 1.0, 0)
	monster.rotation.y = PI / 2.0
	climbed = false
	reached_roof = false
	for i in range(300):
		if climbed:
			rv.position.z -= 0.08
			rv.rotate_y(0.003)
			player.global_position = rv.to_global(Vector3(0, 2.5, 0))
		await _tick()
		monster._physics_process(1.0 / 60.0)
		climbed = climbed or monster.locomotion_state == monster.LocomotionState.CLIMBING
		if climbed and monster.locomotion_state == monster.LocomotionState.NORMAL:
			var local: Vector3 = rv.to_local(monster.global_position)
			reached_roof = local.y > 2.1 and local.x < 2.0
			print("Monster top-out: ", monster.position)
			break
	_expect(climbed, "Monster autonomously grabs actual RV wall to pursue roof player.")
	_expect(reached_roof, "Monster autonomously reaches the actual RV roof.")
	player.position = Vector3(20, 10, 0)
	monster.position = Vector3(25, 10, 0)
	for actor in [player, monster]:
		rv.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))
		actor.position = Vector3(2.65, 2.0, 0)
		actor.rotation.y = PI / 2.0
		actor.locomotion_state = actor.LocomotionState.CLIMBING
		actor.active_climb_rv = rv
		actor.previous_climb_rv_transform = rv.global_transform
		actor.active_wall_normal = Vector3.RIGHT
		actor._sync_body_collision_to_locomotion()
		var anchor: Vector3 = rv.to_local(actor.global_position)
		for i in range(60):
			rv.position.z -= 0.12
			rv.rotate_y(0.005)
			await _tick()
			actor._apply_rv_delta_compensation()
		_expect(rv.to_local(actor.global_position).distance_to(anchor) < 0.08, "%s follows a turning RV without drifting." % actor.name)
		actor._abort_climb("test release")
		_expect(actor.velocity.length() > 5.0, "%s inherits vehicle velocity on release." % actor.name)
		_expect(not actor.body_collision_shape.disabled, "%s never disables its climbing capsule." % actor.name)
		actor.position = Vector3(20, 10, 0)

	# Seated players must move with the vehicle so pursuing monsters see them there.
	var seat: Node3D = rv.get_node("DriverSeat")
	player.enter_seat_mode(seat)
	rv.position += Vector3(3, 0, 4)
	player._physics_process(1.0 / 60.0)
	_expect(player.global_position.is_equal_approx(seat.global_position), "Seated target follows the moving driver's seat.")
	player.exit_seat_mode(Vector3(20, 10, 0))
	# Full-body sweeps must stop at overhead obstacles while climbing.
	var obstruction := StaticBody3D.new()
	var obstruction_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 0.2, 3)
	obstruction_shape.shape = box
	obstruction.add_child(obstruction_shape)
	world.add_child(obstruction)
	obstruction.position = Vector3(20, 5, 0)
	player.position = Vector3(20, 3, 0)
	await _tick()
	var ceiling_collision = player._move_with_climb_collision(Vector3.UP * 4.0)
	_expect(ceiling_collision != null and player.position.y < 3.2, "Climbing body sweep cannot pass through an overhead obstacle.")
	obstruction.queue_free()
	player.position = Vector3(20, 10, 0)
	# Nearby equipment behind a wall cannot be damaged via chassis ancestry.
	rv.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))
	var hidden := Equipment.new()
	hidden.freeze = true
	var hidden_shape := CollisionShape3D.new()
	var small := SphereShape3D.new()
	small.radius = 0.1
	hidden_shape.shape = small
	hidden.add_child(hidden_shape)
	rv.add_child(hidden)
	hidden.position = Vector3(1.3, 1.0, 0)
	monster.position = Vector3(2.5, 1.2, 0)
	monster.attack_timer = 0.0
	await _tick()
	_expect(not monster._has_attack_line_of_sight_to_target(hidden), "RV wall occludes interior equipment.")
	_expect(not monster._try_auto_attack_touching_targets(player, [], [hidden]), "Touch attack cannot bypass the occluding wall.")
	_expect(hidden.current_health == hidden.max_health, "Hidden equipment remains undamaged.")
	hidden.queue_free()
	# A roof monster must damage and eventually remove the supporting panel.
	rv.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))
	player.enter_seat_mode(seat)
	monster.position = Vector3(0, 3.7, -3.5)
	monster.velocity = Vector3.ZERO
	monster.released_carrier_velocity = Vector3.ZERO
	monster.rv_support.clear()
	monster.attack_timer = 0.0
	var ceiling: Node3D = rv.get_node("Ceiling")
	var initial_health: float = ceiling.current_health
	for i in range(900):
		rv.position.z -= 0.04
		rv.rotate_y(0.001)
		await _tick()
		player._physics_process(1.0 / 60.0)
		monster._physics_process(1.0 / 60.0)
		if not is_instance_valid(ceiling):
			break
	_expect(not is_instance_valid(ceiling) or ceiling.current_health < initial_health, "Monster damages roof above a seated driver.")
	_expect(not is_instance_valid(ceiling), "Repeated attacks destroy the actual supporting roof panel.")
	for i in range(45):
		await _tick()
		monster._physics_process(1.0 / 60.0)
	_expect(rv.to_local(monster.global_position).y < 2.0, "Monster falls when its supporting roof is destroyed.")
	world.queue_free()
	await _tick()
	if failures.is_empty():
		print("PASS: moving RV climbing integration")
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
