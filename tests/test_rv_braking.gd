extends SceneTree
## Real wheel physics after controlled initial-speed setup on flat ground.
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	var distances: Array[float] = []
	for scenario in [{"speed": 5.0, "pedal": 1.0, "min": 1.5, "max": 5.0}, {"speed": 10.0, "pedal": 1.0, "min": 6.0, "max": 13.0}, {"speed": 20.0, "pedal": 1.0, "min": 22.0, "max": 42.0}, {"speed": -6.0, "pedal": 1.0, "min": 2.0, "max": 6.0}, {"speed": 10.0, "pedal": 0.5, "min": 10.0, "max": 25.0}]:
		var world := Node3D.new()
		root.add_child(world)
		current_scene = world
		var ground := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(400, 0.2, 400)
		shape.shape = box
		ground.add_child(shape)
		ground.position.y = -0.1
		world.add_child(ground)
		var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
		shell.position.y = 1.8
		world.add_child(shell)
		var rv: Chassis = shell.get_node("Chassis")
		rv.allow_test_controls = true
		for i in range(120): await physics_frame
		rv.handbrake = false
		rv.control_override = {"brake": 0.0}
		for i in range(30): await physics_frame
		rv.linear_velocity = -rv.global_basis.z * float(scenario.speed)
		await physics_frame
		var start := rv.global_position
		var initial_speed := absf(rv.linear_velocity.dot(rv.global_basis.z))
		rv.control_override = {"brake": scenario.pedal}
		var ticks := 0
		while ticks < 600:
			await physics_frame
			ticks += 1
			if ticks == 2: check(rv.brake_input > 0.0 and rv.brake_input < scenario.pedal, "Pedal builds pressure over multiple physics ticks")
			if absf(rv.linear_velocity.dot(rv.global_basis.z)) < 0.1: break
		var distance := Vector2(rv.global_position.x - start.x, rv.global_position.z - start.z).length()
		distances.append(distance)
		print("BRAKE speed=%.2f pedal=%.1f time=%.3f distance=%.3f" % [initial_speed, scenario.pedal, ticks / 60.0, distance])
		check(ticks < 600 and distance >= scenario.min and distance <= scenario.max, "Service brake stops progressively at speed %.0f" % scenario.speed)
		check(not rv.energy.engine_running, "Service braking works with the engine off")
		rv.control_override = {"brake": 0.0}
		for i in range(15): await physics_frame
		check(rv.brake_input == 0.0 and rv.brake == 0.0, "Releasing the pedal fully releases service braking")
		rv.handbrake = true
		for i in range(2): await physics_frame
		check(rv.brake == rv.parking_braking_force and rv.brake > rv.max_braking_force, "Parking brake retains independent holding force")
		var parked := rv.global_position
		for i in range(60): await physics_frame
		check(Vector2(rv.global_position.x - parked.x, rv.global_position.z - parked.z).length() < 0.1, "Parking brake holds the stopped RV")
		world.free()
		await process_frame
	check(distances[2] > distances[1] * 2.5, "Faster approach requires materially more stopping distance")
	check(distances[4] > distances[1] * 1.3, "Partial pedal braking is weaker than full pedal")
	for failure in failures: push_error("FAIL: " + failure)
	if failures.is_empty(): print("PASS: progressive wheel braking, reverse, engine-off braking and parking hold")
	quit(0 if failures.is_empty() else 1)
