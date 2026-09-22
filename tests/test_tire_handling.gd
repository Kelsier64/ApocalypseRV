extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func fixture() -> Chassis:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 0.2, 300)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.1
	world.add_child(ground)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 1.8
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.allow_test_controls = true
	return rv

func run() -> void:
	var results := {}
	for mask in range(16):
		var rv := fixture()
		for i in range(90): await physics_frame
		for slot in range(4):
			if mask & (1 << slot): rv.puncture_wheel(slot)
		rv.handbrake = false
		rv.set_engine_running(true)
		rv.gear = 2
		rv.linear_velocity = -rv.global_basis.z * 8.0
		rv.control_override = {"throttle": 1.0}
		var start := rv.global_position
		for i in range(180): await physics_frame
		var yaw := rv.rotation.y
		var speed := rv.linear_velocity.length()
		var distance := rv.global_position.distance_to(start)
		check(rv.global_basis.y.dot(Vector3.UP) > 0.8, "mask %d stays upright" % mask)
		check(distance > 1, "mask %d can limp" % mask)
		results[mask] = {"yaw": yaw, "speed": speed, "distance": distance}
		print("TIRES mask=%d yaw=%.4f speed=%.3f distance=%.3f" % [mask, yaw, speed, distance])
		rv.control_override = {"brake": 1.0}
		for i in range(240): await physics_frame
		check(rv.linear_velocity.length() < 0.4, "mask %d brakes to rest" % mask)
		current_scene.queue_free()
		await process_frame
		await process_frame
	check(results[1].yaw * results[2].yaw < 0, "Left and right front flats pull in opposite directions")
	check(results[1].yaw < -0.05 and results[2].yaw > 0.05, "Front punctures pull toward the damaged side")
	check(results[4].yaw * results[8].yaw < 0, "Left and right rear flats pull in opposite directions")
	check(absf(results[5].yaw) > absf(results[1].yaw), "Two same-side flats compound pull")
	check(absf(results[3].yaw) < absf(results[1].yaw), "Paired front flats cancel most asymmetric pull")
	check(results[15].speed < results[3].speed and results[3].speed < results[0].speed, "More flat tires reduce maintained speed")
	check(results[12].speed < results[3].speed, "Rear flats lose drive compared with front flats")
	for variant in ["countersteer", "reverse", "fast"]:
		var car := fixture()
		for i in range(90): await physics_frame
		car.puncture_wheel(0)
		car.handbrake = false
		car.set_engine_running(true)
		car.gear = -1 if variant == "reverse" else 4
		car.linear_velocity = Vector3(0, 0, 5 if variant == "reverse" else (-22 if variant == "fast" else -8))
		car.control_override = {"throttle": 1.0, "steering": 0.27 if variant == "countersteer" else 0.0}
		var start := car.global_position
		for i in range(180): await physics_frame
		check(car.global_basis.y.dot(Vector3.UP) > 0.8, "%s with a flat stays upright" % variant)
		if variant == "countersteer": check(absf(car.rotation.y) < absf(results[1].yaw), "Driver can countersteer against flat pull")
		if variant == "reverse": check(car.global_position.z > start.z + 1, "Flat tire still allows reverse")
		print("TIRE_CONTROL %s yaw=%.4f speed=%.3f" % [variant, car.rotation.y, car.linear_velocity.length()])
		current_scene.queue_free()
		await process_frame
		await process_frame
	# Real Area overlap + grounded wheel sweeps. A chassis overlapping the
	# sensor must not puncture all tires at once; front and rear arrive in order.
	var rv := fixture()
	for i in range(90): await physics_frame
	var spike := TireSpikeStrip.new()
	current_scene.add_child(spike)
	spike.position = Vector3(1.5, 0.02, -12)
	rv.handbrake = false
	rv.set_engine_running(true)
	rv.gear = 2
	rv.linear_velocity = Vector3(0, 0, -30)
	rv.control_override = {"throttle": 1.0}
	var front_first := false
	for i in range(180):
		await physics_frame
		if rv.wheel_health[0] == 0 and rv.wheel_health[2] > 0: front_first = true
	check(front_first, "Actual strip punctures front before rear")
	check(rv.wheel_health[0] == 0 and rv.wheel_health[2] == 0, "Actual strip punctures only crossed track")
	check(rv.wheel_health[1] > 0 and rv.wheel_health[3] > 0, "Opposite side tires remain intact")
	current_scene.queue_free()
	await process_frame
	RoadsideKit.scenes.clear()
	RoadsideKit.meshes.clear()
	RoadsideKit.materials.clear()
	await physics_frame
	await process_frame
	if failures.is_empty(): print("PASS: All 16 tire combinations and real spike contact")
	else:
		for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
