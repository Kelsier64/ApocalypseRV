extends SceneTree
## Production preparation, optional equipment and physically safe one-way gate.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("FAIL: " + message)

func wait_phase(run: StartRun, expected: String, frames := 360) -> bool:
	for index in range(frames):
		if run.phase == expected: return true
		await physics_frame
	return run.phase == expected

func _run() -> void:
	var world: Node3D = load("res://world/main_world.tscn").instantiate()
	world.get_node("WorldGenerator").world_seed = 42
	root.add_child(world)
	current_scene = world
	check(await world.wait_for_play(), "Production world becomes usable while preparing")
	var run: StartRun = world.get_node("StartRun")
	if not is_instance_valid(run.gate):
		check(false, "Generated starting shelter binds its physical gate")
		world.free()
		quit(1)
		return
	var clock: WorldClock = world.get_node("WorldClock")
	var player: CharacterBody3D = world.get_node("Player")
	var rv: Chassis = world.get_node("NewRv/Chassis")
	# Decorative wings must be real obstacles, without walkable rooms inside.
	var extension: Node3D = run.shelter.get_node("ExteriorExtension")
	for local_point in [Vector3(-17, 1, 0), Vector3(17, 1, 0), Vector3(0, 1, -22)]:
		var point: Vector3 = run.shelter.to_global(local_point)
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 20, point, 1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider == extension.get_node("Collision"), "Expanded decorative mass blocks physical entry: " + str(local_point))
		var nearest := NavigationServer3D.map_get_closest_point(world.get_world_3d().navigation_map, point)
		check(nearest.distance_to(point) > 3.0, "Sealed extension has no interior floor navigation: " + str(local_point))
	player.set_physics_process(false)
	rv.freeze = true
	rv.set_physics_process(false)
	check(run.phase == "preparing" and not clock.running and not clock.weather_running, "Preparation pauses time and weather")
	check(run.gate.progress == 0.0 and run.gate.stable(), "New garage starts physically closed")
	check(rv.has_working_engine() and rv.energy.battery != null and rv.current_fuel > 0.0, "Starter RV is driveable without loading optional services")
	var mounted_tablet: Equipment = rv.get_node("TabletScreen")
	check(mounted_tablet.mount_support == rv.get_node("RightFront") and mounted_tablet.global_basis.y.dot(-rv.global_basis.x) > 0.99, "Starter tablet is visibly attached to the inside front panel")
	var floor_devices: Array[Equipment] = []
	for name in ["Generator", "CraftingStation", "Scrapper"]:
		check(not rv.has_node(name), "Starter RV omits optional " + name)
		var scene := "res://equipment/%s.tscn" % {"Generator": "generator", "CraftingStation": "crafting_station", "Scrapper": "scrapper"}[name]
		var found := false
		for actor in WorldEntities.get_container(world).get_children():
			if actor is Equipment and actor.scene_file_path == scene and actor.get_connected_rv() == null:
				found = true
				floor_devices.append(actor)
		check(found, "Garage supplies loose optional " + name)
	var targets := [Vector3(-1.15, 0.5, 3), Vector3(-1.15, 0.5, 0.5), Vector3(1.1, 0.5, -2.2)]
	for index in range(floor_devices.size()):
		var device := floor_devices[index]
		var events := [0]
		device.availability_changed.connect(func(): events[0] += 1)
		player.enter_ui_mode()
		device.start_placement(player)
		check(not device.is_being_placed, "UI mode prevents lifting " + device.equipment_name)
		player.exit_ui_mode()
		device.start_placement(player)
		check(player.is_placing_equipment() and device.is_being_placed, "Player authorizes lifting " + device.equipment_name)
		var target: Vector3 = targets[index]
		player.global_position = rv.to_global(Vector3(0, 0.65, target.z + 0.8))
		player.camera.global_position = rv.to_global(Vector3(target.x, 2, target.z + 0.8))
		player.camera.look_at(rv.to_global(target))
		player.placement.update_ghost(player)
		check(player.placement.can_place_equipment and player.placement.target_support == rv, "Real floor ray validates " + device.equipment_name + ": " + player.placement.message)
		if not player.placement.can_place_equipment:
			var cancel := InputEventMouseButton.new()
			cancel.button_index = MOUSE_BUTTON_RIGHT
			cancel.pressed = true
			player.placement.handle_input(player, cancel)
			continue
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		player.placement.handle_input(player, click)
		check(not player.is_placing_equipment() and not device.is_being_placed, "Left click completes placing " + device.equipment_name)
		check(device.get_connected_rv() == rv and device.mount_support == rv and device.get_parent() == rv, "Placed device preserves real RV/support ownership: " + device.equipment_name)
		check(device.can_operate() and events[0] >= 2, "Placement notifies availability and powers " + device.equipment_name)
		await physics_frame
	var before := clock.elapsed_seconds
	for frame in range(15): await physics_frame
	check(clock.elapsed_seconds == before, "Preparation clock does not advance")
	var monster: Monster = load("res://enemies/raker.tscn").instantiate()
	WorldEntities.get_container(world).add_child(monster)
	monster.global_position = Vector3(300, 1, -200)
	check(monster.process_mode == Node.PROCESS_MODE_DISABLED, "New monster respects owning world's preparation gate")
	var feedback := run.begin_run(player)
	check(not feedback.is_empty() and run.phase == "opening", "Button starts the journey once")
	check(clock.running and clock.weather_running and monster.process_mode == Node.PROCESS_MODE_INHERIT, "Button immediately resumes simulation and actors")
	check(not run.save_block_reason().is_empty(), "Opening refuses transitional saves")
	check(await wait_phase(run, "started"), "Gate reaches fully open and started")
	check(run.gate.is_open() and run.save_block_reason().is_empty(), "Fully open gate is stable")
	var inside: Vector3 = run.gate.global_transform * Vector3(0, 0.1, -3)
	var outside: Vector3 = run.gate.global_transform * Vector3(0, 0.1, 3)
	var path := NavigationServer3D.map_get_path(world.get_world_3d().navigation_map, inside, outside, true)
	check(not path.is_empty() and path[path.size() - 1].distance_to(outside) < 2.0, "Navigation crosses the open physical doorway: inside=%s outside=%s nearest_inside=%s nearest_outside=%s path=%s" % [inside, outside, NavigationServer3D.map_get_closest_point(world.get_world_3d().navigation_map, inside), NavigationServer3D.map_get_closest_point(world.get_world_3d().navigation_map, outside), path])
	run.begin_run(player)
	check(run.phase == "started", "Repeated button does not restart the gate")
	monster.queue_free()
	# The player can already be outside while part of the RV remains near the door.
	player.global_position = run.gate.global_transform * Vector3(0, 1, 9)
	rv.global_transform = run.gate.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.8, 10))
	check(not run.departure_clear(), "Vehicle rear must clear the door before sealing")
	rv.global_transform = run.gate.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.8, 32))
	var tablet: Equipment = rv.get_node("TabletScreen")
	var tablet_pose := tablet.transform
	tablet.position = Vector3(0, 1, -30)
	check(not run.vehicle_clear(rv), "Clearance includes protruding mounted equipment")
	tablet.transform = tablet_pose
	player.global_position = run.gate.global_transform * Vector3(0, 1, 3)
	check(not run.departure_clear(), "Player must also be eight metres outside")
	player.global_position = run.gate.global_transform * Vector3(0, 1, 9)
	check(run.departure_clear(), "Complete RV and player departure is recognized")
	check(await wait_phase(run, "closing", 90), "Departure starts permanent closing")
	check(not run.save_block_reason().is_empty(), "Closing refuses transitional saves")
	var obstruction: Prop = load("res://props/scrap.tscn").instantiate()
	obstruction.freeze = true
	WorldEntities.get_container(world).add_child(obstruction)
	obstruction.global_position = run.gate.global_transform * Vector3(-1.75, 1, 0)
	check(await wait_phase(run, "started", 90), "Occupied closing sweep reopens instead of crushing")
	for frame in range(160): await physics_frame
	check(run.phase == "started" and run.gate.is_open(), "Obstruction keeps the exit open")
	obstruction.queue_free()
	await physics_frame
	check(await wait_phase(run, "sealed", 360), "Clear doorway retries closing and permanently seals")
	check(run.gate.progress == 0.0 and run.save_block_reason().is_empty(), "Sealed gate is closed and stable")
	var ray := PhysicsRayQueryParameters3D.create(run.gate.global_transform * Vector3(-1.75, 1, -1), run.gate.global_transform * Vector3(-1.75, 1, 1), 1)
	var wall := world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not wall.is_empty() and wall.collider == run.gate.left, "Sealed physical leaf blocks return through the doorway")
	run.begin_run(player)
	check(run.phase == "sealed", "Button cannot reopen a sealed garage")
	var original := run.shelter
	var replacement: Node3D = load("res://world/starting_shelter/starting_shelter.tscn").instantiate()
	replacement.transform = original.global_transform
	world.add_child(replacement)
	run.bind_shelter(replacement, run.shelter_site)
	check(run.phase == "sealed" and run.gate.progress == 0.0, "Reconstructed shelter retains permanent closure")
	original.queue_free()
	if failures.is_empty(): print("PASS: starting shelter preparation, optional equipment, departure and occupied permanent gate")
	world.free()
	quit(0 if failures.is_empty() else 1)
