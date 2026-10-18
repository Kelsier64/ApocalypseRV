extends "res://tests/test_training_maintenance.gd"
## All nine production lessons, physical exit completion and terminal ownership.
## Lesson one uses wheel forces; later lessons reuse real transaction fixtures.
# Keep Item alive through Godot 4.7.2's script-list shutdown traversal.
# Engine fix: https://github.com/godotengine/godot/pull/117991 (4.8).
# The continuous journey inherits this compatibility pin too.
static var _shutdown_base_scripts: Array[Script] = [Item]
var forward_peak := 0.0
var reverse_peak := 0.0
var completed_snapshot: Dictionary = {}

func _run() -> void:
	root.size = Vector2i(1280, 720)
	checkpoint = root.get_node("Checkpoint")
	world = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.profile = generator.profile.duplicate()
	generator.profile.generation_version = 11
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	generator.world_seed = 42
	root.add_child(world)
	current_scene = world
	if not check(await world.wait_for_play() and await WAIT.generator_idle(self, generator), "Nine-lesson production world becomes playable"):
		await finish(); return
	tutorial = world.get_node("StartRun/Tutorial")
	if not check(await WAIT.until(self, func(): return tutorial.initialized() and not tutorial.entry_snapshot.is_empty(), 60000, true), "Fresh lesson has an independent first-stage entry"):
		await finish(); return
	_bind_fixture()
	stage_entries[1] = tutorial.entry_snapshot.duplicate(true)
	if not await retry_current(1): await finish(); return
	if not check_restored_battery(stage_entries[1]): await finish(); return
	if not await driving_lesson(): await finish(); return
	_bind_fixture()
	# Let Jolt apply the frozen-body handoff before transaction code reads its
	# native velocity. A frame written by the final wheel step may still be pending.
	for tick in 3: await physics_frame
	_bind_fixture()
	if not await stage_ready(2): await finish(); return
	if not await battery_lesson(): await finish(); return
	if not await console_lesson(): await finish(); return
	if not await placement_lesson(): await finish(); return
	if not await restart_recycling_lesson(): await finish(); return
	if not await recycling_lesson(): await finish(); return
	if not await manufacturing_lesson(): await finish(); return
	if not await continue_training(): await finish(); return
	if not await reload_stage_entries(): await finish(); return
	if not await skip_without_terminal(): await finish(); return
	if not await skip_with_inventory_terminal(): await finish(); return
	if not await reload_completed(): await finish(); return
	print("TRAINING_COMPLETION_SPEEDS: forward=", forward_peak, " reverse=", reverse_peak)
	await finish()

func stage_ready(expected: int) -> bool:
	if not await super.stage_ready(expected): return false
	if not stage_entries.has(expected): stage_entries[expected] = tutorial.entry_snapshot.duplicate(true)
	return true

func retry_current(expected: int) -> bool:
	var entry: Dictionary = tutorial.entry_snapshot.duplicate(true)
	if not check(await tutorial.restart_stage(), "Stage %d invokes actual in-memory retry" % expected): return false
	world = current_scene
	if not check(await WAIT.generator_idle(self, world.get_node("WorldGenerator")) and await WAIT.retired_candidates(self, checkpoint), "Stage %d retry settles replacement world" % expected): return false
	_bind_fixture()
	return check(tutorial.stage == expected and tutorial.entry_snapshot == entry and tutorial.can_restart(), "Stage %d retry retains exact independent entry" % expected)

func driving_lesson() -> bool:
	# Resume production actors after the retry helper's stable transaction setup.
	vehicle.freeze = false
	vehicle.set_physics_process(true)
	player.set_physics_process(true)
	var terminal: TrainingTerminal = tutorial.designated_terminal()
	if not check(terminal != null and terminal.can_operate(), "First lesson has the real mounted training terminal"): return false
	terminal.interact_hold(player)
	if not check(await WAIT.until(self, func(): return tutorial.flags.viewed, 5000), "Actual Conditions presentation records lesson one"): return false
	terminal._close_ui()
	var flashlight: Item = workshop.by_id(tutorial.flashlight_id)
	if not check(flashlight != null, "First lesson retains its physical flashlight"): return false
	flashlight.interact(player)
	await frames()
	if not check(tutorial.flags.flashlight and select_item(tutorial.flashlight_id), "Actual first-lesson pickup transfers flashlight ownership"): return false
	var seat: Item = vehicle.get_node("DriverSeat")
	seat.interact_hold(player)
	if not check(player.seated_in == seat and vehicle.is_player_driving, "Actual seat grants first-lesson driving ownership"): return false
	vehicle.allow_test_controls = true
	if not check(await drive_to_local_z(-362.0, 1, 2.0) and await stop_and_park(), "Real wheels drive to the premature first parking attempt"): return false
	check(tutorial.flags.marker_index == 1 and not tutorial.flags.parked and tutorial.stage == 1, "Parking before marker 02 cannot finish the first lesson")
	if not check(await drive_to_local_z(-337.0, 1, 2.0), "Real wheels cross both ordered lane markers"): return false
	check(tutorial.flags.marker_index == 2 and not tutorial.flags.reversed, "Forward lane traversal retains the reversal requirement")
	if not check(await drive_to_local_z(-362.0, -1, 1.6), "Real wheel forces reverse into the marked parking bay"): return false
	if not check(await stop_and_park(true), "Engine-off handbraked parking advances the actual first lesson"): return false
	check(tutorial.flags.viewed and tutorial.flags.flashlight and tutorial.flags.marker_index == 2 and tutorial.flags.reversed and tutorial.flags.parked, "All five first-lesson conditions came from real gameplay")
	check(forward_peak <= 3.0 and reverse_peak <= 2.0, "Wheel-driven replay retains bounded forward and reverse speeds")
	seat.exit_seat()
	if not check(player.seated_in == null and not vehicle.is_player_driving, "Normal seat exit releases driving before workshop handoff"): return false
	vehicle.control_override.clear()
	await physics_seconds(0.1)
	return true

func check_restored_battery(saved: Dictionary) -> bool:
	var sockets: Array[BatterySocket] = []
	for node: Node in vehicle.find_children("*", "", true, false):
		if node is BatterySocket: sockets.append(node)
	if not check(sockets.size() == 1, "First-stage retry restores exactly one battery socket without default stock"):
		print_battery_sockets("unexpected restored socket count")
		return false
	for record: Dictionary in saved.vehicles:
		if record.id != vehicle.persistent_id: continue
		for item: Dictionary in record.mounted_items:
			if item.scene != "res://rv/battery_socket.tscn": continue
			return check(sockets[0].persistent_id == item.state.id and sockets[0].installed_battery != null and sockets[0].installed_battery.id == item.state.service.battery.id, "First-stage retry retains the saved socket and battery identities")
	return check(false, "First-stage retry contains a saved battery socket")

func mount(key: String, local: Vector3) -> bool:
	if not check(player.enter_equipment_placement(), "Inventory " + key + " opens an actual placement preview"): return false
	# Keep the preset item box at (1.25, 0.8, 3.7); the rear-right deck provides
	# a separate real support surface with room for the scrapper and its hopper.
	if key == "scrapper": local.z = 5.0
	# The actual driving exit can leave a different actor orientation from the
	# fresh workshop fixture. Stand in the front cabin, clear of both machines.
	player.global_position = vehicle.to_global(Vector3(0, 0.55, -2.5))
	for adjustment in [Vector3.ZERO, Vector3(-0.15, 0, 0), Vector3(0, 0, 0.3), Vector3(-0.15, 0, 0.3)]:
		var target: Vector3 = local + adjustment
		await physics_frame
		# Production eye follow may reset the camera on the physics frame after
		# driving. Set the controlled ray afterward and query/commit synchronously.
		player.camera.global_position = vehicle.to_global(target + Vector3(0, 1.4, -0.8))
		player.camera.look_at(vehicle.to_global(target), vehicle.global_basis.y)
		player.placement.update_ghost(player)
		if player.placement.can_place_equipment and RVConnection.resolve(player.placement.target_support) == vehicle: break
	if not check(player.placement.can_place_equipment and RVConnection.resolve(player.placement.target_support) == vehicle, "Real RV deck ray validates " + key + " placement: " + player.placement.message):
		print("TRAINING_PLACEMENT: player=", player.global_transform, " player_local=", vehicle.to_local(player.global_position),
			" camera=", player.camera.global_transform, " preview=", player.placement.placing_equipment.global_transform,
			" preview_local=", vehicle.to_local(player.placement.placing_equipment.global_position), " vehicle_basis=", vehicle.global_basis,
			" support=", player.placement.target_support, " blocker=", player.placement.message)
		player.cancel_equipment_placement()
		return false
	if not check(player.placement.commit(player), "Validated " + key + " preview commits through inventory ownership"): return false
	await physics_frame
	await frames()
	var installed: Item = workshop.item(key)
	return check(installed != null and installed.can_operate() and installed.get_connected_rv() == vehicle, "Committed " + key + " retains its designated identity and RV service")

func print_battery_sockets(label: String, designated: BatterySocket = null) -> void:
	var registered: Array[Node] = vehicle.get_equipment()
	print("TRAINING_BATTERY_SOCKETS: ", label, " rv=", vehicle.get_path(), " rv_id=", vehicle.persistent_id,
		" designated_instance=", designated.get_instance_id() if designated != null else 0)
	print_battery_children(vehicle, registered)
	for saved_vehicle: Dictionary in tutorial.entry_snapshot.get("vehicles", []):
		if saved_vehicle.id != vehicle.persistent_id: continue
		for saved: Dictionary in saved_vehicle.mounted_items:
			if saved.scene == "res://rv/battery_socket.tscn":
				print("TRAINING_BATTERY_SAVED: socket_id=", saved.state.id, " battery=", saved.state.service.get("battery", {}))

func print_battery_children(node: Node, registered: Array[Node]) -> void:
	if node is BatterySocket:
		var socket: BatterySocket = node
		print("TRAINING_BATTERY_SOCKET: path=", socket.get_path(), " id=", socket.persistent_id,
			" instance=", socket.get_instance_id(), " registered=", socket in registered,
			" fixed=", socket.is_fixed, " enabled=", socket.enabled, " operable=", socket.can_operate(),
			" preinstalled=", socket.preinstalled_battery, " battery_id=", socket.installed_battery.id if socket.installed_battery != null else "",
			" battery_instance=", socket.installed_battery.get_instance_id() if socket.installed_battery != null else 0)
	for child in node.get_children(): print_battery_children(child, registered)

func planar_speed() -> float:
	return vehicle.linear_velocity.slide(run_owner.shelter.global_basis.y.normalized()).length()

func physics_seconds(seconds: float) -> void:
	for tick in ceili(seconds * Engine.physics_ticks_per_second): await physics_frame

func stop_and_park(expect_advancement := false) -> bool:
	vehicle.control_override = {"brake": 1.0}
	var stopped := await WAIT.until(self, func() -> bool:
		return planar_speed() <= 0.1 and vehicle.angular_velocity.length() <= 0.04, 15000, true)
	vehicle.set_handbrake(true)
	vehicle.set_engine_running(false)
	await physics_seconds(1.2)
	if expect_advancement:
		return stopped and await WAIT.until(self, func(): return tutorial.stage == 2, 5000, true)
	return stopped

func drive_to_local_z(target: float, gear: int, speed_limit: float) -> bool:
	if not vehicle.set_gear(gear) or not vehicle.set_engine_running(true): return false
	vehicle.set_handbrake(false)
	var direction := 1.0 if gear > 0 else -1.0
	var deadline := Time.get_ticks_msec() + 120000
	var ticks := 0
	while ticks < ceili(120.0 * Engine.physics_ticks_per_second) and Time.get_ticks_msec() < deadline:
		var local := run_owner.shelter.to_local(vehicle.global_position)
		var remaining := (target - local.z) * direction
		var speed := vehicle.linear_velocity.length()
		if gear > 0: forward_peak = maxf(forward_peak, speed)
		else: reverse_peak = maxf(reverse_peak, speed)
		if remaining <= 0.35:
			vehicle.control_override = {"brake": 1.0}
			if speed <= 0.1 and vehicle.angular_velocity.length() <= 0.04:
				return absf(local.z - target) < 1.0 and absf(local.x) < 2.5
		else:
			var desired := minf(speed_limit, maxf(0.4, sqrt(maxf(0.0, remaining - 0.2) * 1.2)))
			if speed > desired + 0.08:
				vehicle.control_override = {"brake": clampf((speed - desired) * 0.7, 0.04, 1.0)}
			else:
				vehicle.control_override = {"throttle": clampf((desired - speed) * 0.8, 0.0, 0.65)}
		if local.y < -1.0 or absf(local.x) > 3.0 or vehicle.global_basis.y.y < 0.8: return false
		await physics_frame
		ticks += 1
	vehicle.control_override = {"brake": 1.0}
	return false

func continue_training() -> bool:
	if not await super.continue_training(): return false
	if not await refueling_lesson(): return false
	return await departure_lesson()

func refueling_lesson() -> bool:
	var service: TutorialService = tutorial.service
	var gasoline_id: String = workshop.gasoline_id
	var port: Item = vehicle.get_node("FuelPort")
	if not check(select_item(gasoline_id) and not service.flags.refueled, "Stage eight retains the actually manufactured fuel can"): return false
	vehicle.current_fuel = 0.0
	await physics_seconds(0.1)
	check(vehicle.current_fuel >= 10.0 and not service.flags.refueled and tutorial.stage == 8, "Preparation fuel reserve never counts as a refuel transaction")
	vehicle.current_fuel = vehicle.max_fuel
	var inventory: Array[Dictionary] = player.inventory.items.duplicate(true)
	port.interact(player)
	check(not service.flags.refueled and player.inventory.items == inventory, "Full tank rejects fuel with no completion or inventory consumption")
	var current: Dictionary = checkpoint.capture_world(world)
	if not check(not current.is_empty() and checkpoint.validation_error(current).is_empty(), "Rejected fuel attempts retain a valid stage-eight current checkpoint"): return false
	if not await load_and_verify(current, "Stage-eight fuel current checkpoint"): return false
	if not await retry_current(8): return false
	service = tutorial.service
	port = vehicle.get_node("FuelPort")
	if not check(select_item(gasoline_id), "Stage-eight retry restores the original manufactured can"): return false
	var before: float = vehicle.current_fuel
	var slots_before: int = player.inventory.items.size()
	var expected_amount: float = minf(vehicle.fuel_per_gas_can, vehicle.max_fuel - before)
	port.interact(player)
	check(service.flags.refueled and service.fuel_can_id == gasoline_id and is_equal_approx(service.fuel_amount, expected_amount), "Successful real fuel-port transfer records the designated can and actual amount")
	check(is_equal_approx(vehicle.current_fuel, before + expected_amount) and player.inventory.items.size() == slots_before and not select_item(gasoline_id), "Refuel adds fuel, consumes filled can and retains inventory size")
	check(select_item(service.empty_can_id) and player.inventory.active_item().scene_path == "res://props/gas_can_empty.tscn", "Fuel-port transaction creates the real returned empty can")
	return await stage_ready(9)

func departure_lesson() -> bool:
	var service: TutorialService = tutorial.service
	check(not service.flags.departure and run_owner.phase == "preparing", "Stage nine remains active until the real departure button accepts")
	var current: Dictionary = checkpoint.capture_world(world)
	if not await load_and_verify(current, "Stage-nine current checkpoint"): return false
	if not await retry_current(9): return false
	service = tutorial.service
	var hatch: Node = vehicle.get_node("EngineBay/Hatch")
	var button: Node = run_owner.shelter.get_node("GarageButton")
	check(hatch.opened and not tutorial.can_departure(), "Open maintenance hatch blocks stage-nine departure")
	button.interact(player)
	check(run_owner.phase == "preparing" and not service.flags.departure, "Rejected departure button records no journey event")
	hatch.interact(player)
	if not check(await WAIT.until(self, func(): return hatch.stable() and not hatch.opened, 5000, true), "Real maintenance hatch closes before departure"): return false
	if not check(tutorial.can_departure() and tutorial.departure_block_reason().is_empty(), "Repaired current RV and stable closed hatch permit departure"): return false
	button.interact(player)
	check(service.flags.departure and run_owner.phase == "opening" and world.get_node("WorldClock").running, "Actual departure button starts simulation and records departure once")
	check(not tutorial.can_restart() and not tutorial.can_skip() and not run_owner.save_block_reason().is_empty(), "Journey start disables retry/skip and transitional saving")
	vehicle.current_fuel = 0.0
	vehicle.current_power = 0.0
	await physics_seconds(0.1)
	check(vehicle.current_fuel == 0.0 and vehicle.current_power == 0.0, "Preparation fuel and battery reserve stops after the accepted button")
	vehicle.current_power = 10.0
	if not check(await WAIT.until(self, func(): return run_owner.phase == "started" and run_owner.gate.is_open(), 10000, true), "Exit physically opens before departure"): return false
	var gate: ShelterGarageGate = run_owner.gate
	player.global_position = gate.to_global(Vector3(0, 1, 9))
	vehicle.global_transform = gate.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.8, 10))
	check(not run_owner.vehicle_clear(vehicle) and not run_owner.departure_clear(), "RV rear collision must cross the exit threshold")
	await physics_seconds(0.5)
	check(tutorial.status == "active" and run_owner.phase == "started", "Partly exited RV cannot complete training")
	vehicle.global_transform = gate.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.8, 32))
	var terminal: TrainingTerminal = tutorial.designated_terminal()
	var terminal_pose := terminal.transform
	terminal.position = Vector3(0, 1, -30)
	check(not run_owner.vehicle_clear(vehicle), "Clearance includes terminal collision extending behind the RV")
	terminal.transform = terminal_pose
	player.global_position = gate.to_global(Vector3(0, 1, 3))
	check(not run_owner.departure_clear(), "Player must cross the exit threshold as well")
	player.global_position = gate.to_global(Vector3(0, 1, 9))
	if not check(await WAIT.until(self, func(): return run_owner.phase == "closing", 5000, true), "Whole RV and player clearance starts physical closing"): return false
	var obstruction: Item = load("res://props/scrap.tscn").instantiate()
	obstruction.freeze = true
	WorldEntities.get_container(world).add_child(obstruction)
	obstruction.global_position = gate.to_global(Vector3(-1.75, 1, 0))
	if not check(await WAIT.until(self, func(): return run_owner.phase == "started" and gate.is_open(), 10000, true), "Real rigid-body obstruction reopens the closing exit"): return false
	check(gate.sweep_occupied() and tutorial.status == "active" and not terminal.manual_unlocked, "Obstructed closure keeps the exit and training active")
	obstruction.queue_free()
	await physics_frame
	if not check(await WAIT.until(self, func(): return run_owner.phase == "sealed", 10000, true), "Cleared real doorway physically seals the exit"): return false
	check(gate.stable() and gate.progress == 0.0 and tutorial.status == "completed" and tutorial.entry_snapshot.is_empty(), "Only actual closure completes training and removes retry state")
	check(terminal.manual_unlocked and terminal.completion == "completed" and terminal.persistent_id == tutorial.terminal_id, "Completion unlocks the same original terminal")
	terminal.interact_hold(player)
	check(terminal.ui_instance.visible and terminal.ui_instance.current_page == "manual", "Completed original terminal opens searchable Manual")
	terminal._close_ui()
	var ray := PhysicsRayQueryParameters3D.create(gate.to_global(Vector3(-1.75, 1, -1)), gate.to_global(Vector3(-1.75, 1, 1)), 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider == gate.left, "Sealed physical leaf blocks return to the shelter")
	button.interact(player)
	check(run_owner.phase == "sealed", "Departure button cannot reopen the sealed shelter")
	completed_snapshot = checkpoint.capture_world(world)
	return check(not completed_snapshot.is_empty() and checkpoint.validation_error(completed_snapshot).is_empty(), "Completed sealed journey captures a valid persistent checkpoint")

func load_raw(saved: Dictionary, label: String) -> bool:
	if not check(await checkpoint.load_snapshot(world, saved), label + " performs actual world replacement"): return false
	world = current_scene
	if not check(await WAIT.generator_idle(self, world.get_node("WorldGenerator")) and await WAIT.retired_candidates(self, checkpoint), label + " settles its candidate"): return false
	_bind_fixture()
	return true

func skip_without_terminal() -> bool:
	if not await load_and_verify(stage_entries[3], "Skip branch partial-stage entry"): return false
	var identity := tutorial.terminal_id
	tutorial.designated_terminal().queue_free()
	await frames()
	var menu: CanvasLayer = player.get_node("SettingsMenu")
	if not check(menu.open_menu(), "Esc settings remains usable with the terminal lost"): return false
	menu._show_skip_tutorial()
	menu._cancel_modal()
	check(tutorial.status == "active" and menu.visible, "Cancelling real Skip confirmation preserves partial training")
	menu._show_skip_tutorial()
	menu._accept_modal()
	if not check(await WAIT.until(self, func(): return tutorial.status == "skipped" and run_owner.save_block_reason().is_empty(), 10000, true), "Esc Skip succeeds with the designated terminal absent"): return false
	check(run_owner.phase == "preparing" and not world.get_node("WorldClock").running and tutorial.entry_snapshot.is_empty(), "Skip opens the route while keeping preparation until departure")
	check(workshop.by_id(identity) == null and not tutorial.can_restart() and not tutorial.can_skip(), "Skip fabricates no replacement terminal and cannot re-enter training")
	for index in 8:
		check(run_owner.bay_unlocked(index) and run_owner.shelter.get_node("Gates").get_child(index).is_open(), "Skip opens actual inner gate %d" % (index + 1))
	var skipped: Dictionary = checkpoint.capture_world(world)
	if not check(not skipped.is_empty() and checkpoint.validation_error(skipped).is_empty(), "Terminal-free Skip captures a valid checkpoint"): return false
	if not await load_raw(skipped, "Terminal-free skipped checkpoint"): return false
	if not check(tutorial.status == "skipped" and tutorial.designated_terminal() == null and run_owner.phase == "preparing", "Reload preserves Skip without respawning its absent terminal"): return false
	run_owner.shelter.get_node("GarageButton").interact(player)
	check(run_owner.phase == "opening" and tutorial.status == "skipped" and world.get_node("WorldClock").running, "Actual button starts skipped journey simulation while retaining the Skipped record")
	vehicle.current_fuel = 0.0
	vehicle.current_power = 0.0
	await physics_seconds(0.1)
	check(vehicle.current_fuel == 0.0 and vehicle.current_power == 0.0, "Skipped departure stops preparation fuel and battery reserve")
	if not check(await WAIT.until(self, func(): return run_owner.phase == "started" and run_owner.gate.is_open(), 10000, true), "Skipped journey physically opens its exit"): return false
	var gate: ShelterGarageGate = run_owner.gate
	vehicle.global_transform = gate.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.8, 32))
	player.global_position = gate.to_global(Vector3(0, 1, 9))
	check(run_owner.departure_clear(), "Controlled skipped exit clears all RV collision corners and the player")
	if not check(await WAIT.until(self, func(): return run_owner.phase == "sealed", 10000, true), "Skipped journey physically seals after whole-RV departure"): return false
	check(tutorial.status == "skipped" and tutorial.designated_terminal() == null and gate.progress == 0.0 and gate.stable(), "Sealed skipped journey preserves its record and creates no replacement manual")
	var skipped_departure: Dictionary = checkpoint.capture_world(world)
	return check(not skipped_departure.is_empty() and checkpoint.validation_error(skipped_departure).is_empty(), "Sealed skipped journey captures a valid persistent checkpoint")

func skip_with_inventory_terminal() -> bool:
	if not await load_and_verify(stage_entries[3], "Inventory manual branch entry"): return false
	var terminal: TrainingTerminal = tutorial.designated_terminal()
	var identity := terminal.persistent_id
	terminal.pickup(player)
	await frames()
	if not check(select_item(identity) and not player.inventory.active_item().state.training_terminal.manual_unlocked, "Original terminal enters locked normal inventory"): return false
	var locked_record: Dictionary = player.inventory.active_item()
	if not check(ItemState.valid(locked_record.scene_path, locked_record.state) and VehicleSnapshot.valid_item(locked_record), "Normal locked terminal inventory record passes Item and checkpoint validation"):
		print("TRAINING_TERMINAL_INVENTORY: ", locked_record)
		return false
	var unrelated: TrainingTerminal = load("res://equipment/training_terminal.tscn").instantiate()
	WorldEntities.get_container(world).add_child(unrelated)
	var unrelated_id := unrelated.persistent_id
	if not check(tutorial.skip_tutorial(), "Skip supports a terminal owned by inventory"): return false
	check(select_item(identity) and player.inventory.active_item().state.training_terminal.manual_unlocked and player.inventory.active_item().state.training_terminal.completion == "skipped", "Skip unlocks the exact original inventory record")
	var unlocked_record: Dictionary = player.inventory.active_item()
	if not check(ItemState.valid(unlocked_record.scene_path, unlocked_record.state) and VehicleSnapshot.valid_item(unlocked_record), "Skip keeps the unlocked terminal inventory record valid without changing its size"):
		print("TRAINING_TERMINAL_INVENTORY: ", unlocked_record)
		return false
	check(not unrelated.manual_unlocked and unrelated.persistent_id == unrelated_id, "Skip cannot unlock unrelated training terminals")
	if not check(await WAIT.until(self, func(): return run_owner.save_block_reason().is_empty(), 10000, true), "Skipped inventory world settles all route gates"): return false
	var saved: Dictionary = checkpoint.capture_world(world)
	if not check(not saved.is_empty() and checkpoint.validation_error(saved).is_empty(), "Skipped inventory terminal captures valid checkpoint state"): return false
	var owners: Dictionary = ownership(saved, identity)
	check(owners.inventory == 1 and owners.world == 0 and owners.mounted == 0 and owners.stored == 0, "Skipped terminal has exactly one real inventory owner")
	if not await load_raw(saved, "Skipped inventory terminal checkpoint"): return false
	check(select_item(identity) and player.inventory.active_item().state.training_terminal.manual_unlocked, "Reload retains unlocked same-ID inventory terminal")
	check(workshop.by_id(unrelated_id) != null and not workshop.by_id(unrelated_id).manual_unlocked, "Reload leaves the unrelated terminal locked")
	player.drop_item()
	await frames()
	var dropped: TrainingTerminal = workshop.by_id(identity)
	if not check(dropped != null and dropped.manual_unlocked and dropped.completion == "skipped", "Dropping reloaded inventory creates the same unlocked Item"): return false
	dropped.confirm_placement(dropped.global_transform, vehicle)
	dropped.interact_hold(player)
	check(dropped.ui_instance.visible and dropped.ui_instance.current_page == "manual" and not dropped.is_management_active(), "Remounted original opens Manual with no rvctl construction authority")
	dropped._close_ui()
	return true

func reload_completed() -> bool:
	if not await load_raw(completed_snapshot, "Completed nine-lesson checkpoint"): return false
	var terminal: TrainingTerminal = tutorial.designated_terminal()
	check(tutorial.status == "completed" and tutorial.stage == 9 and run_owner.phase == "sealed" and tutorial.entry_snapshot.is_empty(), "Completed checkpoint restores sealed journey with no retry")
	check(terminal != null and terminal.manual_unlocked and terminal.completion == "completed", "Completed checkpoint retains original manual unlock")
	check(not tutorial.can_restart() and not tutorial.can_skip() and not tutorial.can_departure(), "Completed checkpoint cannot restart, skip or depart again")
	return true
