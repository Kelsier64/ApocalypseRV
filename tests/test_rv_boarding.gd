extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func crate(world: Node3D, point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	body.position = point
	world.add_child(body)
	return body
func _run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	crate(world, Vector3(0, -0.1, 0), Vector3(60, 0.2, 60))
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.position.y = 0.95
	rv.freeze = true
	rv.set_physics_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(10, 0, 0)
	await physics_frame
	await physics_frame
	var ramp: RearRamp = rv.rear_ramp
	check(ramp.interact(player).contains("後門"), "Closed doors prevent ramp deployment")
	rv.get_node("RearDoor").restore_angles([-deg_to_rad(100), deg_to_rad(100)])
	await physics_frame
	var obstacle := crate(world, rv.to_global(Vector3(0, 0.5, 7.0)), Vector3(0.6, 1, 0.6))
	await physics_frame
	check(ramp.interact(player).contains("擋住") and not ramp.deployed, "Deployment detects obstacles")
	obstacle.free()
	await physics_frame
	var result := ramp.interact(player)
	check(ramp.moving and rv.drive_blocked() and VehicleSnapshot.capture(rv).is_empty(), "Moving ramp locks driving and saving")
	for i in range(200): await physics_frame
	check(ramp.deployed, "Ramp deploys on level ground: " + result)
	if not ramp.deployed:
		for failure in failures: push_error(failure)
		quit(1)
		return
	check(absf(ramp.angle) <= deg_to_rad(30), "Ramp stays within walkable slope")
	var ramp_saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.apply(rv, ramp_saved) and ramp.deployed, "Deployed ramp and door angles survive vehicle restore")
	await physics_frame
	var cargo := crate(world, ramp.to_global(Vector3(0, -0.2, 0.8)), Vector3(0.4, 0.4, 0.4))
	await physics_frame
	check(ramp.interact(player).contains("無法收起") and ramp.deployed, "Cargo blocks ramp retraction")
	cargo.free()
	rv.set_engine_running(true)
	rv.is_player_driving = true
	rv.handbrake = false
	rv.allow_test_controls = true
	rv.control_override = {"throttle": 1.0}
	rv._physics_process(0.016)
	check(rv.energy.engine_running and rv.engine_force == 0 and rv.brake > 0, "Deployed ramp permits idle but blocks drive")
	rv.control_override.clear()
	rv.is_player_driving = false
	rv.set_engine_running(false)
	rv.handbrake = true
	var incoming := EngineState.new()
	var item := incoming.item()
	player.add_item(item.name, true, item.scene_path, item.state)
	player.position = Vector3(0, 0.02, 10.5)
	player.rotation = Vector3.ZERO
	player.set_physics_process(true)
	Input.action_press("move_forward")
	for i in range(150): await physics_frame
	Input.action_release("move_forward")
	check(player.global_position.z < rv.global_position.z + 5.6 and player.global_position.y > 0.7, "Player carrying engine walks up ramp and through rear doors: " + str(player.global_position))
	check(player.inventory.active_item().state.engine.id == incoming.id, "Boarding keeps held engine")
	for i in range(180):
		Input.action_press("move_forward")
		await physics_frame
	Input.action_release("move_forward")
	check(rv.to_local(player.global_position).z < -2.0, "Continuous central aisle reaches cockpit: " + str(rv.to_local(player.global_position)))
	player.set_physics_process(false)
	player.position = ramp.to_global(Vector3(0, -0.5, 1.6))
	await physics_frame
	check(ramp.interact(player).contains("無法收起") and ramp.deployed, "Occupied ramp cannot retract")
	player.position = Vector3(12, 0, 0)
	await physics_frame
	check(ramp.interact(player).contains("收起中") and rv.drive_blocked(), "Empty ramp starts retracting with driving locked")
	for i in range(200): await physics_frame
	check(not ramp.deployed and not rv.drive_blocked(), "Fully stowed ramp unlocks driving")
	var steep := crate(world, Vector3(0, 0.4, 9.54), Vector3(3, 0.2, 2))
	steep.rotation.x = deg_to_rad(40)
	await physics_frame
	check(ramp.interact(player).contains("平穩地面") and not ramp.deployed, "Ground steeper than 30 degrees rejects deployment")
	steep.free()
	rv.position.y = 4.0
	await physics_frame
	check(not ramp.interact(player).contains("已展開") and not ramp.deployed, "Excessive height rejects deployment")
	rv.position.y = 0.95
	await physics_frame
	# Use actual seat and collider. Completely blocked exits must keep seat ownership.
	var seat: Equipment = rv.get_node("DriverSeat")
	player.inventory.items.clear()
	player.refresh_inventory()
	seat.interact_hold(player)
	var block := crate(world, rv.to_global(Vector3(0, 1.5, 0)), Vector3(5, 3, 14))
	await physics_frame
	seat.exit_seat()
	check(seat.current_driver == player and player.seated_in == seat and not seat.exit_message.is_empty(), "Blocked normal exit stays seated")
	block.free()
	await physics_frame
	seat.exit_seat()
	player.set_physics_process(false)
	check(player.seated_in == null and rv.to_local(player.global_position).y < 0.7, "Clear exit uses supported aisle floor")
	# Free placement rotation/translation remains validated and fixed sockets stay canonical.
	seat.interact_hold(player)
	block = crate(world, rv.to_global(Vector3(0, 1.5, 0)), Vector3(5, 3, 14))
	await physics_frame
	seat.take_damage(999)
	check(player.seated_in == null, "Destroyed seat forces release even with aisle blocked")
	block.free()
	player.set_physics_process(false)
	var device: Equipment = rv.get_node("Generator")
	player.position = Vector3(0, 1, 2)
	player.camera.global_position = rv.to_global(Vector3(0, 2, 2))
	player.camera.look_at(rv.to_global(Vector3(0, 0.5, 1.5)))
	device.start_placement(player)
	player.placement.update_ghost(player)
	var before := device.global_basis
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_E
	player.placement.handle_input(player, event)
	player.placement.update_ghost(player)
	check(not before.is_equal_approx(device.global_basis), "E rotates free equipment preview")
	event.physical_keycode = KEY_RIGHT
	var before_position := device.global_position
	player.placement.handle_input(player, event)
	player.placement.update_ghost(player)
	check(is_equal_approx(device.global_position.distance_to(before_position), 0.05), "Arrow nudges 5cm on surface")
	var cancel := InputEventMouseButton.new()
	cancel.pressed = true
	cancel.button_index = MOUSE_BUTTON_RIGHT
	player.placement.handle_input(player, cancel)
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: rear ramp safety, actual engine boarding, aisle, supported exits and placement adjustments")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
