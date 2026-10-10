extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func ticks(original_count: int) -> int:
	return ceili(original_count * Engine.physics_ticks_per_second / 60.0)
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
	var ground := crate(world, Vector3(0, -0.1, 0), Vector3(60, 0.2, 60))
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
	var control: Node3D = ramp.get_node("Control")
	var camera_rest: Transform3D = player.camera.transform
	player.camera.global_position = control.to_global(Vector3(-0.1, 0.25, 0.9))
	player.camera.look_at(control.global_position)
	var control_ray: RayCast3D = player.camera.get_node("InteractRay")
	control_ray.force_raycast_update()
	check(control_ray.get_collider() == control, "Rear control remains reachable through the production interaction ray with doors closed")
	rv.linear_velocity = Vector3(0, 0, 0.6)
	check(ramp.interact(player).contains("停穩") and not ramp.moving, "Moving vehicle cannot start ramp deployment")
	rv.linear_velocity = Vector3.ZERO
	rv.handbrake = false
	check(ramp.interact(player).contains("手煞車") and not ramp.moving, "Ramp operation still requires the handbrake at startup")
	rv.handbrake = true
	var obstacle := crate(world, rv.to_global(Vector3(0, 0.5, 7.0)), Vector3(0.6, 1, 0.6))
	await physics_frame
	var result := ramp.interact(player)
	check(ramp.moving and rv.drive_blocked() and VehicleSnapshot.capture(rv).is_empty(), "Closed-door deployment ignores props and locks driving and saving")
	for i in ticks(200): await physics_frame
	check(ramp.deployed, "Ramp deploys on level ground: " + result)
	obstacle.free()
	if not ramp.deployed:
		for failure in failures: push_error(failure)
		quit(1)
		return
	check(absf(ramp.angle) <= deg_to_rad(30), "Ramp stays within walkable slope")
	var ramp_saved := VehicleSnapshot.capture(rv)
	check(await VehicleSnapshot.apply(rv, ramp_saved) and ramp.deployed, "Deployed ramp and door angles survive vehicle restore")
	check(is_equal_approx(ramp.angle, ramp_saved.ramp.angle) and is_equal_approx(ramp.length, ramp_saved.ramp.length), "Restore retains supported ramp angle and length")
	rv.get_node("RearDoor").restore_angles([-deg_to_rad(100), deg_to_rad(100)])
	await physics_frame
	player.camera.global_position = control.to_global(Vector3(-0.1, 0.25, 0.9))
	player.camera.look_at(control.global_position)
	control_ray.force_raycast_update()
	check(control_ray.get_collider() == control, "Opening the rear doors leaves the fixed ramp control reachable")
	player.camera.transform = camera_rest
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
	for i in ticks(150): await physics_frame
	Input.action_release("move_forward")
	check(player.global_position.z < rv.global_position.z + 5.6 and player.global_position.y > 0.7, "Player carrying engine walks up ramp and through rear doors: " + str(player.global_position))
	check(player.inventory.active_item().state.engine.id == incoming.id, "Boarding keeps held engine")
	for i in ticks(180):
		Input.action_press("move_forward")
		await physics_frame
	Input.action_release("move_forward")
	check(rv.to_local(player.global_position).z < -2.0, "Continuous central aisle reaches cockpit: " + str(rv.to_local(player.global_position)))
	player.set_physics_process(false)
	player.position = ramp.to_global(Vector3(0, -0.5, 1.6))
	await physics_frame
	check(ramp.interact(player).contains("收起中") and ramp.moving and rv.drive_blocked(), "Occupied ramp starts retracting with driving locked")
	await physics_frame
	check(ramp.deck.disabled and VehicleSnapshot.capture(rv).is_empty(), "Occupied retracting deck disables collision and saving")
	player.position = Vector3(12, 0, 0)
	for i in ticks(200): await physics_frame
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
	ground.collision_layer = 0
	var support_tip := ramp.to_global(Vector3(0, 0, 3.6))
	var narrow_support := crate(world, Vector3(support_tip.x, -0.1, support_tip.z), Vector3(0.3, 0.2, 0.8))
	await physics_frame
	check(ramp.interact(player).contains("展開中") and ramp.moving, "Center ground support is sufficient without either side corner")
	for i in ticks(200): await physics_frame
	check(ramp.deployed, "Ramp fully deploys on narrow center support")
	ramp.interact(player)
	for i in ticks(200): await physics_frame
	ground.collision_layer = 1
	narrow_support.free()
	await physics_frame
	# Use actual seat and collider. Completely blocked exits must keep seat ownership.
	var seat: Item = rv.get_node("DriverSeat")
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
	var device: Item = rv.get_node("Scrapper")
	player.position = Vector3(0, 1, 2)
	player.camera.global_position = rv.to_global(Vector3(0, 2, 2))
	player.camera.look_at(rv.to_global(Vector3(0, 0.5, 1.5)))
	var device_id := device.persistent_id
	check(device.pickup(player).begins_with("已拾取"), "Equipment is picked up before entering placement")
	check(player.enter_equipment_placement(), "Inventory-backed placement starts")
	var preview: Item = player.placement.placing_equipment
	player.placement.update_ghost(player)
	var before := preview.global_basis
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_E
	player.placement.handle_input(player, event)
	player.placement.update_ghost(player)
	check(not before.is_equal_approx(preview.global_basis), "E rotates independent Item preview")
	event.physical_keycode = KEY_RIGHT
	var before_position := preview.global_position
	player.placement.handle_input(player, event)
	player.placement.update_ghost(player)
	check(is_equal_approx(preview.global_position.distance_to(before_position), 0.05), "Arrow nudges 5cm on surface")
	var cancel := InputEventMouseButton.new()
	cancel.pressed = true
	cancel.button_index = MOUSE_BUTTON_RIGHT
	player.placement.handle_input(player, cancel)
	check(not player.is_placing_equipment() and player.inventory.active_item().state.id == device_id, "Cancelling placement keeps the original Item in inventory")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: rear ramp safety, actual engine boarding, aisle, supported exits and placement adjustments")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
