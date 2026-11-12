extends SceneTree
## Real wheel braking on level and sloped ground.
const SERVICE_RV := preload("res://rv/new_rv.tscn")
const STARTER_RV := preload("res://rv/starter_rv.tscn")

var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func duration_ticks(original_count: int) -> int:
	return ceili(original_count * Engine.physics_ticks_per_second / 60.0)

func spawn_rv(scene: PackedScene, height: float, slope: float = 0.0, heading: float = 0.0) -> Chassis:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 0.2, 400)
	shape.shape = box
	shape.position.y = -0.1
	ground.add_child(shape)
	ground.rotation.x = slope
	world.add_child(ground)
	var shell := scene.instantiate() as Node3D
	shell.transform = ground.transform * Transform3D(Basis(Vector3.UP, heading), Vector3(0, height, 0))
	world.add_child(shell)
	return shell.get_node("Chassis")

func run() -> void:
	var distances: Array[float] = []
	for scenario in [{"speed": 5.0, "pedal": 1.0, "min": 1.5, "max": 5.0}, {"speed": 10.0, "pedal": 1.0, "min": 6.0, "max": 13.0}, {"speed": 20.0, "pedal": 1.0, "min": 22.0, "max": 42.0}, {"speed": -6.0, "pedal": 1.0, "min": 2.0, "max": 6.0}, {"speed": 10.0, "pedal": 0.5, "min": 10.0, "max": 25.0}]:
		var rv := spawn_rv(SERVICE_RV, 1.8)
		rv.allow_test_controls = true
		for i in duration_ticks(120): await physics_frame
		rv.handbrake = false
		rv.control_override = {"brake": 0.0}
		for i in duration_ticks(30): await physics_frame
		rv.linear_velocity = -rv.global_basis.z * float(scenario.speed)
		await physics_frame
		var start := rv.global_position
		var initial_speed := absf(rv.linear_velocity.dot(rv.global_basis.z))
		rv.control_override = {"brake": scenario.pedal}
		var ticks := 0
		while ticks < duration_ticks(600):
			await physics_frame
			ticks += 1
			if ticks == 2: check(rv.brake_input > 0.0 and rv.brake_input < scenario.pedal, "Pedal builds pressure over multiple physics ticks")
			if absf(rv.linear_velocity.dot(rv.global_basis.z)) < 0.1: break
		var distance := Vector2(rv.global_position.x - start.x, rv.global_position.z - start.z).length()
		distances.append(distance)
		print("BRAKE speed=%.2f pedal=%.1f time=%.3f distance=%.3f" % [initial_speed, scenario.pedal, float(ticks) / Engine.physics_ticks_per_second, distance])
		check(ticks < duration_ticks(600) and distance >= scenario.min and distance <= scenario.max, "Service brake stops progressively at speed %.0f" % scenario.speed)
		check(not rv.energy.engine_running, "Service braking works with the engine off")
		rv.control_override = {"brake": 0.0}
		for i in duration_ticks(15): await physics_frame
		check(rv.brake_input == 0.0 and rv.brake == 0.0, "Releasing the pedal fully releases service braking")
		rv.handbrake = true
		for i in range(2): await physics_frame
		var impulse_scale := 60.0 / Engine.physics_ticks_per_second
		check(is_equal_approx(rv.brake, rv.parking_braking_force * impulse_scale) and rv.brake > rv.max_braking_force * impulse_scale, "Parking brake retains independent holding force per second")
		var parked := rv.global_position
		for i in duration_ticks(60): await physics_frame
		check(Vector2(rv.global_position.x - parked.x, rv.global_position.z - parked.z).length() < 0.1, "Parking brake holds the stopped RV")
		current_scene.free()
		await process_frame
	check(distances[2] > distances[1] * 2.5, "Faster approach requires materially more stopping distance")
	check(distances[4] > distances[1] * 1.3, "Partial pedal braking is weaker than full pedal")
	await check_parking_hold(0.0, 0.0)
	await check_parking_hold(8.0, 0.0)
	await check_parking_hold(18.0, 90.0)
	for failure in failures: push_error("FAIL: " + failure)
	if failures.is_empty(): print("PASS: progressive wheel braking and parking hold on level ground and slopes")
	quit(0 if failures.is_empty() else 1)

func check_parking_hold(slope_degrees: float, heading_degrees: float) -> void:
	var slope := deg_to_rad(slope_degrees)
	var normal := Vector3.UP.rotated(Vector3.RIGHT, slope)
	var rv := spawn_rv(STARTER_RV, 1.35, slope, deg_to_rad(heading_degrees))
	for i in duration_ticks(180): await physics_frame
	var parked := rv.global_position
	var drift := 0.0
	for i in duration_ticks(1800):
		await physics_frame
		drift = maxf(drift, (rv.global_position - parked).slide(normal).length())
	print("PARKING slope=%.0f heading=%.0f drift=%.3f" % [slope_degrees, heading_degrees, drift])
	check(drift < 0.05, "Parking brake prevents persistent drift on %.0f degree ground" % slope_degrees)
	# Use the longitudinal grade for release. Free-rolling tires still resist sideslip.
	if slope_degrees > 0.0 and heading_degrees == 0.0:
		rv.set_handbrake(false)
		for i in duration_ticks(120): await physics_frame
		check((rv.global_position - parked).slide(normal).length() > 0.5, "Releasing the parking brake lets the RV roll downhill")
		rv.set_handbrake(true)
		await physics_frame
		check(rv.linear_velocity.slide(normal).length() > 0.5, "Applying the parking brake while rolling preserves momentum on the first step")
		for i in duration_ticks(180): await physics_frame
		parked = rv.global_position
		for i in duration_ticks(120): await physics_frame
		check((rv.global_position - parked).slide(normal).length() < 0.1, "Parking brake brings the rolling RV to a stable stop")
	current_scene.free()
	await process_frame
