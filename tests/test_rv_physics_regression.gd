extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 0.2, 200)
	shape.shape = box
	ground.add_child(shape)
	world.add_child(ground)
	var vehicle: Node3D = load("res://rv/new_rv.tscn").instantiate()
	vehicle.position.y = 1.8
	world.add_child(vehicle)
	var rv: Chassis = vehicle.get_node("Chassis")
	rv.contact_monitor = true
	rv.max_contacts_reported = 32
	for tick in range(60):
		await physics_frame
		if tick < 5: print("BASE ", tick, " ", rv.global_position, " ", rv.linear_velocity, " ", rv.get_colliding_bodies().map(func(n): return n.name))
	if rv.global_position.distance_to(Vector3(0, 1.8, 0)) > 2.0: failures.append("Production RV must settle without self-collision propulsion")
	for path in ["generator", "crafting_station", "scrapper", "tablet_screen"]:
		var device: Equipment = load("res://equipment/" + path + ".tscn").instantiate()
		world.add_child(device)
		device.confirm_placement(rv.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.7, 0)), rv)
		for tick in range(30): await physics_frame
		print(path, " position=", rv.global_position, " velocity=", rv.linear_velocity)
		if rv.linear_velocity.length() > 3.0: failures.append("Mounting " + path + " must not launch RV")
		device.queue_free()
		await physics_frame
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: production RV load and mounting physics")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
