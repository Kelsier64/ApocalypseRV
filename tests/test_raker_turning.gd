extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok and note not in failures: failures.append(note)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var actor: Raker = load("res://enemies/raker.tscn").instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.position = Vector3.ZERO
	actor.velocity = Vector3(0, 0, -3.4)
	actor._process_chase(1.0 / 60.0, Vector3(20, 0, 0))
	var flat := actor.velocity.slide(Vector3.UP)
	check(flat.length() < .001 or flat.normalized().dot(-actor.global_basis.z) > .999, "90 degree turn keeps translation aligned with visible facing")
	check(flat.length() < 3.0, "Sharp turn slows instead of full-speed sideways movement")
	actor.rotation = Vector3.ZERO
	actor.velocity = Vector3(0, 0, -3.4)
	actor._process_chase(1.0 / 60.0, Vector3(0, 0, 20))
	check(actor.velocity.slide(Vector3.UP).length() < .01, "Target behind causes turning before backward movement")
	for i in 150: actor._process_chase(1.0 / 60.0, Vector3(0, 0, 20))
	check(actor.velocity.z > 3.3 and (-actor.global_basis.z).dot(Vector3.BACK) > .99, "180 degree turn completes and resumes pursuit")
	actor.rotation = Vector3.ZERO
	actor.reversal_side = 0.0
	var chosen_side := 0.0
	for i in 12:
		var before := actor.rotation.y
		actor.velocity = Vector3(0, 0, -3.4)
		actor._process_chase(1.0 / 60.0, Vector3(.4 if i % 2 == 0 else -.4, 0, 2))
		var change := angle_difference(before, actor.rotation.y)
		if i == 0: chosen_side = signf(change)
		check(change * chosen_side > 0, "Rear target jitter does not flip turn direction")
	# Same elapsed time at two physics rates must give the same heading.
	var angles: Array[float] = []
	for hz in [30, 120]:
		actor.rotation = Vector3.ZERO
		actor.reversal_side = 0.0
		for i in range(hz / 10):
			actor.velocity = Vector3(0, 0, -3.4)
			actor._process_chase(1.0 / hz, Vector3(20, 0, 0))
		angles.append(actor.rotation.y)
	check(absf(angle_difference(angles[0], angles[1])) < .01, "Turning is independent of physics tick rate")
	# Repeated left/right steering at sprint speed must preserve scale and
	# orientation rather than shearing the collider with transform blends.
	for i in 240:
		actor.velocity = Vector3(0, 0, -18)
		actor._process_chase(1.0 / 60.0, Vector3(20 * sin(i * .03), 0, -20))
		flat = actor.velocity.slide(Vector3.UP)
		check(flat.length() <= 18.001, "Turning never adds speed above the sprint cap")
		check(actor.global_basis.get_scale().distance_to(Vector3.ONE) < .001, "Turning preserves capsule and mesh scale")
		check(flat.length() < .001 or flat.normalized().dot(-actor.global_basis.z) > .999, "S turns preserve facing / movement agreement")
	world.free()
	if failures.is_empty(): print("PASS: Raker sharp turns, reversal, facing alignment, tick independence and scale")
	else:
		for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
