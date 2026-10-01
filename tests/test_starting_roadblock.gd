extends SceneTree
## Try the visible wreck pile with production wheels at centre and both shoulders.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(1000, 0.2, 120)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	floor_body.position.y = -0.1
	world.add_child(floor_body)
	var barrier: Node3D = load("res://world/starting_shelter/roadblock.tscn").instantiate()
	barrier.position.z = 20
	world.add_child(barrier)
	for approach_x in [-20.0, 0.0, 20.0]:
		var shell: Node3D = load("res://rv/starter_rv.tscn").instantiate()
		shell.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(approach_x, 1.8, -8))
		world.add_child(shell)
		var rv: Chassis = shell.get_node("Chassis")
		rv.allow_test_controls = true
		for step in range(90): await physics_frame
		var start_z := rv.global_position.z
		rv.set_engine_running(true)
		rv.set_gear(1)
		rv.set_handbrake(false)
		rv.control_override = {"throttle": 0.8}
		var furthest := start_z
		for step in range(900):
			await physics_frame
			furthest = maxf(furthest, rv.global_position.z)
		check(furthest > start_z + 5.0, "Vehicle actually approaches the wrecks at x=%s" % approach_x)
		check(furthest < 18.0, "Wreck bodies stop powered RV before it crosses the pile at x=%s" % approach_x)
		print("ROADBLOCK x=%.1f furthest_z=%.2f" % [approach_x, furthest])
		shell.free()
		await process_frame
	# The broad earthwork joins solid retaining wings rather than open shoulders.
	for x in [-440.0, -100.0, -30.0, 30.0, 100.0, 440.0]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, 9, 10), Vector3(x, 9, 30), 1)
		check(not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Retaining wing blocks the rear ridge at x=%s" % x)
	world.free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: abandoned-car roadblock stops wheel-driven centre/shoulder approaches and closes rear ridge")
	quit(0 if failures.is_empty() else 1)
